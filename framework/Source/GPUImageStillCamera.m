// 2448x3264 pixel image = 31,961,088 bytes for uncompressed RGBA

#import "GPUImageStillCamera.h"
#import <ImageIO/ImageIO.h>

void GPUImageCreateResizedSampleBuffer(CVPixelBufferRef cameraFrame, CGSize finalSize, CMSampleBufferRef *sampleBuffer, GLubyte **imageData)
{
    CGSize originalSize = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));

    CVPixelBufferLockBaseAddress(cameraFrame, 0);
    GLubyte *sourceImageBytes =  CVPixelBufferGetBaseAddress(cameraFrame);
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, sourceImageBytes, CVPixelBufferGetBytesPerRow(cameraFrame) * originalSize.height, NULL);
    CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();    
    CGImageRef cgImageFromBytes = CGImageCreate((int)originalSize.width, (int)originalSize.height, 8, 32, CVPixelBufferGetBytesPerRow(cameraFrame), genericRGBColorspace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, dataProvider, NULL, NO, kCGRenderingIntentDefault);
    
    *imageData = (GLubyte *) calloc(1, (int)finalSize.width * (int)finalSize.height * 4);
    
    CGContextRef imageContext = CGBitmapContextCreate(*imageData, (int)finalSize.width, (int)finalSize.height, 8, (int)finalSize.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(imageContext, CGRectMake(0.0, 0.0, finalSize.width, finalSize.height), cgImageFromBytes);
    CGImageRelease(cgImageFromBytes);
    CGContextRelease(imageContext);
    CGColorSpaceRelease(genericRGBColorspace);
    CGDataProviderRelease(dataProvider);
    
    CVPixelBufferRef pixel_buffer = NULL;
    CVPixelBufferCreateWithBytes(kCFAllocatorDefault, finalSize.width, finalSize.height, kCVPixelFormatType_32BGRA, *imageData, finalSize.width * 4, NULL, NULL, NULL, &pixel_buffer);
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel_buffer, &videoInfo);
    
    CMTime frameTime = CMTimeMake(1, 30);
    CMSampleTimingInfo timing = {frameTime, frameTime, kCMTimeInvalid};
    
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixel_buffer, YES, NULL, NULL, videoInfo, &timing, sampleBuffer);
    CFRelease(videoInfo);
    CVPixelBufferRelease(pixel_buffer);
}

@interface GPUImageStillCamera ()
{
    AVCaptureStillImageOutput *photoOutput;
}

@end

@implementation GPUImageStillCamera

#pragma mark -
#pragma mark Initialization and teardown

- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition;
{
    if (!(self = [super initWithSessionPreset:sessionPreset cameraPosition:cameraPosition]))
    {
		return nil;
    }
    
    [self.captureSession beginConfiguration];
    
    photoOutput = [[AVCaptureStillImageOutput alloc] init];
    [photoOutput setOutputSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    [self.captureSession addOutput:photoOutput];
    
    [self.captureSession commitConfiguration];
    
    return self;
}

- (id)init;
{
    if (!(self = [self initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:AVCaptureDevicePositionBack]))
    {
		return nil;
    }
    return self;
}

- (void)removeInputsAndOutputs;
{
    [self.captureSession removeOutput:photoOutput];
    [super removeInputsAndOutputs];
}

#pragma mark -
#pragma mark Photography controls

/*- (void)capturePhotoAsSampleBufferWithCompletionHandler:(void (^)(CMSampleBufferRef imageSampleBuffer, NSError *error))block
{
    [photoOutput captureStillImageAsynchronouslyFromConnection:[[photoOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
#error If you want to use this method, you must comment out the line in initWithSessionPreset:cameraPosition: which sets the CVPixelBufferPixelFormatTypeKey. However, if you do this you cannot use any of the below methods to take a photo if you also supply a filter.
        block(imageSampleBuffer, error);
    }];
    
    return;
}*/

- (void)capturePhotoAsImageWithCompletionHandler:(void (^)(UIImage *capturedImage, NSDictionary *metadata, NSError *error))block
{
    [photoOutput captureStillImageAsynchronouslyFromConnection:[[photoOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
        
        UIImage *capturedImage = nil;
        NSDictionary *metadata = nil;
        
        if (imageSampleBuffer != NULL)
        {
            CFDictionaryRef metadataDictCF = CMCopyDictionaryOfAttachments(NULL, imageSampleBuffer, kCMAttachmentMode_ShouldPropagate);
            metadata = [[NSDictionary alloc] initWithDictionary:(__bridge NSDictionary*)metadataDictCF];
            CFRelease(metadataDictCF);
            
            CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(imageSampleBuffer);
            CVPixelBufferLockBaseAddress(imageBuffer, 0);
            uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
            CGImageRef cgImage = CGBitmapContextCreateImage(context);
            
            UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
            UIImageOrientation imageOrientation = UIImageOrientationLeft;
            BOOL backCamera = ([[videoInput device] position] == AVCaptureDevicePositionBack);
            switch (deviceOrientation)
            {
                default:
                case UIDeviceOrientationPortrait:
                    imageOrientation = UIImageOrientationRight;
                    break;
                case UIDeviceOrientationPortraitUpsideDown:
                    imageOrientation = UIImageOrientationLeft;
                    break;
                case UIDeviceOrientationLandscapeLeft:
                    imageOrientation = backCamera ? UIImageOrientationUp : UIImageOrientationDown;
                    break;
                case UIDeviceOrientationLandscapeRight:
                    imageOrientation = backCamera ? UIImageOrientationDown : UIImageOrientationUp;
                    break;
            }

            
            capturedImage = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:imageOrientation];
            CGContextRelease(context);
            CGColorSpaceRelease(colorSpace);
            CGImageRelease(cgImage);
        }
        
        block(capturedImage, metadata, error);
    }];
    
    return;
}

- (void)capturePhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block;
{
    [photoOutput captureStillImageAsynchronouslyFromConnection:[[photoOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {

        // For now, resize photos to fix within the max texture size of the GPU
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(imageSampleBuffer);
        
        CGSize sizeOfPhoto = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));
        CGSize scaledImageSizeToFitOnGPU = [GPUImageOpenGLESContext sizeThatFitsWithinATextureForSize:sizeOfPhoto];
        if (!CGSizeEqualToSize(sizeOfPhoto, scaledImageSizeToFitOnGPU))
        {
            CMSampleBufferRef sampleBuffer;
            GLubyte *imageData;
            GPUImageCreateResizedSampleBuffer(cameraFrame, scaledImageSizeToFitOnGPU, &sampleBuffer, &imageData);
            
            [self captureOutput:photoOutput didOutputSampleBuffer:sampleBuffer fromConnection:[[photoOutput connections] objectAtIndex:0]];
            CFRelease(sampleBuffer);
            
            free(imageData);
        }
        else
        {
            [self captureOutput:photoOutput didOutputSampleBuffer:imageSampleBuffer fromConnection:[[photoOutput connections] objectAtIndex:0]];
        }        

        UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentlyProcessedOutput];
        
        block(filteredPhoto, error);        
    }];
    
    return;
}

- (void)capturePhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(NSData *processedJPEG, NSError *error))block;
{
//    report_memory(@"Before still image capture");
    [photoOutput captureStillImageAsynchronouslyFromConnection:[[photoOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
//        report_memory(@"Before filter processing");

        // For now, resize photos to fix within the max texture size of the GPU
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(imageSampleBuffer);

        CGSize sizeOfPhoto = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));
        CGSize scaledImageSizeToFitOnGPU = [GPUImageOpenGLESContext sizeThatFitsWithinATextureForSize:sizeOfPhoto];
        if (!CGSizeEqualToSize(sizeOfPhoto, scaledImageSizeToFitOnGPU))
        {
            CMSampleBufferRef sampleBuffer;
            GLubyte *imageData;
            GPUImageCreateResizedSampleBuffer(cameraFrame, scaledImageSizeToFitOnGPU, &sampleBuffer, &imageData);
            
            [self captureOutput:photoOutput didOutputSampleBuffer:sampleBuffer fromConnection:[[photoOutput connections] objectAtIndex:0]];
            CFRelease(sampleBuffer);
            
            free(imageData);
        }
        else
        {
            // This is a workaround for the corrupt images that are sometimes returned when taking a photo with the front camera and using the iOS 5.0 texture caches
            AVCaptureDevicePosition currentCameraPosition = [[videoInput device] position];
            if ( (currentCameraPosition != AVCaptureDevicePositionFront) || (![GPUImageOpenGLESContext supportsFastTextureUpload]))
            {
                [self captureOutput:photoOutput didOutputSampleBuffer:imageSampleBuffer fromConnection:[[photoOutput connections] objectAtIndex:0]];
            }
        }        

//        report_memory(@"After filter processing");
        
        __strong NSData *dataForJPEGFile = nil;
        @autoreleasepool {
            UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentlyProcessedOutput];
            
//            report_memory(@"After UIImage generation");

            dataForJPEGFile = UIImageJPEGRepresentation(filteredPhoto, 0.8);
//            report_memory(@"After JPEG generation");
        }

//        report_memory(@"After autorelease pool");

        block(dataForJPEGFile, error);        
    }];
    
    return;
}

- (void)capturePhotoAsPNGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(NSData *processedPNG, NSError *error))block;
{
    [photoOutput captureStillImageAsynchronouslyFromConnection:[[photoOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
        
        // For now, resize photos to fix within the max texture size of the GPU
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(imageSampleBuffer);
        
        CGSize sizeOfPhoto = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));
        CGSize scaledImageSizeToFitOnGPU = [GPUImageOpenGLESContext sizeThatFitsWithinATextureForSize:sizeOfPhoto];
        if (!CGSizeEqualToSize(sizeOfPhoto, scaledImageSizeToFitOnGPU))
        {
            CMSampleBufferRef sampleBuffer;
            GLubyte *imageData;
            GPUImageCreateResizedSampleBuffer(cameraFrame, scaledImageSizeToFitOnGPU, &sampleBuffer, &imageData);
            
            [self captureOutput:photoOutput didOutputSampleBuffer:sampleBuffer fromConnection:[[photoOutput connections] objectAtIndex:0]];
            CFRelease(sampleBuffer);
            
            free(imageData);
        }
        else
        {
            [self captureOutput:photoOutput didOutputSampleBuffer:imageSampleBuffer fromConnection:[[photoOutput connections] objectAtIndex:0]];
        }        
        
        NSData *dataForPNGFile = nil;
        @autoreleasepool { 
            UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentlyProcessedOutput];
            dataForPNGFile = UIImagePNGRepresentation(filteredPhoto);
        }
        
        block(dataForPNGFile, error);        
    }];
    
    return;
}


@end
