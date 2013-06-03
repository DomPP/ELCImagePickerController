//
//  ELCImagePickerController.m
//  ELCImagePickerDemo
//
//  Created by ELC on 9/9/10.
//  Copyright 2010 ELC Technologies. All rights reserved.
//

#import "ELCImagePickerController.h"
#import "ELCAsset.h"
#import "ELCAssetCell.h"
#import "ELCAssetTablePicker.h"
#import "ELCAlbumPickerController.h"

@interface ELCImagePickerController (){
    
}

@property (nonatomic, retain) NSMutableArray *imageQueue;
@property (nonatomic, retain) NSMutableArray *videoQueue;
@property (nonatomic, retain) NSMutableArray *processedAssets;
@property (nonatomic, assign) NSInteger processCount;
@property (nonatomic, assign) NSInteger processTotal;

@property (nonatomic, retain) UIProgressView *progessView;
@end
@implementation ELCImagePickerController

#pragma mark - Properties 
@synthesize delegate = _myDelegate;
@synthesize
imageQueue = _imageQueue,
videoQueue = _videoQueue,
processedAssets = _processedAssets;

- (void)cancelImagePicker
{
	if([_myDelegate respondsToSelector:@selector(elcImagePickerControllerDidCancel:)]) {
		[_myDelegate performSelector:@selector(elcImagePickerControllerDidCancel:) withObject:self];
	}
}

#pragma mark - Accept asset dictionaries

//called from album picker. assets holds dictionaries for all assets picked from the photo album
- (void)selectedAssets:(NSArray *)assets
{
	
    //pull out video files and process separately
    //queue completed assets in array
    //once all are processed, send the dictionary array to the delegate
	for(ALAsset *asset in assets) {
        
        NSString *assetType = [asset valueForProperty:ALAssetPropertyType];

        
        //move video to tmp file
        if ([assetType isEqualToString:ALAssetTypeVideo]) {
            if (!self.videoQueue) {
                self.videoQueue = [NSMutableArray array];
            }
            
            [self.videoQueue addObject:asset];
        }else{
            if (!self.imageQueue) {
                self.imageQueue = [NSMutableArray array];
            }
            
            [self.imageQueue addObject:asset];
        }
    }
    self.processCount =  self.imageQueue.count + self.videoQueue.count;
    self.processTotal = self.processCount-1;
    self.processedAssets = [NSMutableArray arrayWithCapacity:self.processCount];
    [self startProcessing];
    
//    NSURL *refUrl = [[asset valueForProperty:ALAssetPropertyURLs] valueForKey:[[[asset valueForProperty:ALAssetPropertyURLs] allKeys] objectAtIndex:0]];
//    refUrl = [self videoAssetURLToTempFile:refUrl];
    
}

#pragma mark - handle processing events
//checks if all assets have been processed and notifies delegate if everything is done
-(void)assetProcessed{
//    NSLog(@"<processed asset> asset count:%d",self.processCount);
//    NSLog(@"total:%d count:%d",_processTotal, _processCount);
    CGFloat progress = (CGFloat)(_processTotal - _processCount) / _processTotal;
    [self.progessView setProgress:progress animated:YES];
    
    
    NSLog(@"<finished processing>");
    
    if(_myDelegate != nil && [_myDelegate respondsToSelector:@selector(elcImagePickerController:didFinishPickingMediaWithInfo:)]) {
		[_myDelegate performSelector:@selector(elcImagePickerController:didFinishPickingMediaWithInfo:) withObject:self withObject:[NSArray arrayWithArray:self.processedAssets]];
	} else {
//        [self popToRootViewControllerAnimated:NO];
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    
    if (self.processCount == 0){
        [self hideProgressView];
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

//starts processing on queues once the assets have been sorted
-(void)startProcessing{
    if (_processCount == 0) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    
    dispatch_queue_t backgroundQueue = dispatch_queue_create("com.razeware.imagegrabber.bgqueue", NULL);
    [self showProgressView];
    
    for (ALAsset *asset in self.imageQueue) {
        NSURL *url = [[asset valueForProperty:ALAssetPropertyURLs] valueForKey:[[[asset valueForProperty:ALAssetPropertyURLs] allKeys] objectAtIndex:0]];
        url = [NSURL fileURLWithPath:[self tmpPathForAssetURL:url]];
//            [self processAsset:asset withURL:url];
        dispatch_async(backgroundQueue, ^(void) {
            [self processAsset:asset withURL:url];
        });

    }
    
    for (ALAsset *asset in self.videoQueue) {
//            [self videoAssetToTempFile:asset];
        dispatch_async(backgroundQueue, ^(void) {
            [self videoAssetToTempFile:asset];
        });
        
    }
}

//pulls out relevant info from the asset object
-(void)processAsset:(ALAsset*)asset withURL:(NSURL*)fileURL{
    
    //initialize asset dictionary
    NSMutableDictionary *workingDictionary = [[NSMutableDictionary alloc] init];

    //pull out type
    NSString *assetType = [asset valueForProperty:ALAssetPropertyType];
    [workingDictionary setObject:assetType forKey:@"UIImagePickerControllerMediaType"];

    //pull out image
    ALAssetRepresentation *assetRep = [asset defaultRepresentation];
    CGImageRef imgRef = [assetRep fullScreenImage];
    UIImage *img = [UIImage imageWithCGImage:imgRef
                                       scale:[UIScreen mainScreen].scale
                                 orientation:UIImageOrientationUp];
    [workingDictionary setObject:img forKey:@"UIImagePickerControllerOriginalImage"];
    
    //pull out reference URL: this property is a file url for videos; for images it's used as the file name since the full image is returned;
//    NSURL *refUrl = [[asset valueForProperty:ALAssetPropertyURLs] valueForKey:[[[asset valueForProperty:ALAssetPropertyURLs] allKeys] objectAtIndex:0]];
    [workingDictionary setObject:fileURL forKey:@"UIImagePickerControllerReferenceURL"];
    
//    if ([assetType isEqualToString:ALAssetTypeVideo]) {
//        [self.videoQueue removeObject:asset];
//    }else{
//        [self.imageQueue removeObject:asset];
//    }
    self.processCount--;
    [self.processedAssets removeAllObjects];
    [self.processedAssets addObject:workingDictionary];
    [workingDictionary release];
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self assetProcessed];
    });
    
}

#pragma mark - helper functions
-(NSString *)tmpPathForAssetURL:(NSURL*) assetUrl{
    NSString * surl = [assetUrl absoluteString];
    NSString * ext = [surl substringFromIndex:[surl rangeOfString:@"ext="].location + 4];
    NSTimeInterval ti = [[NSDate date]timeIntervalSinceReferenceDate];
    NSString * filename = [NSString stringWithFormat: @"%f.%@",ti,ext];
    NSString * tmpfile = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    return tmpfile;
}

-(void)showProgressView{
    //build parent view
    UIView *parentView = [[UIView alloc] initWithFrame:CGRectMake(0,
                                                                  0,
                                                                  CGRectGetWidth(self.view.frame),
                                                                  CGRectGetHeight(self.view.frame))];
    parentView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.8];
    

    //build activty indicator
    UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    activityView.center = parentView.center;
    [activityView startAnimating];
    
    //build progress view
    self.progessView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progessView.frame = CGRectMake(0,
                                        CGRectGetMaxY(activityView.frame)+16,
                                        CGRectGetWidth(self.view.frame),
                                        CGRectGetHeight(_progessView.frame));

    //build label
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0,
                                                               0,
                                                               CGRectGetWidth(self.view.frame),
                                                               50)];
    label.text = @"Getting media from library";
    label.textColor = [UIColor whiteColor];
    [label setFont:[UIFont fontWithName:label.font.fontName size:20 ]];
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = NSTextAlignmentCenter;
    
    //add subviews
    [parentView addSubview:self.progessView];
    [parentView addSubview:label];
    [parentView addSubview:activityView];
    [self.view addSubview:parentView];
    
    //clean up
    [label release];
    [parentView release];
    [_progessView release];
    [activityView release];
}

-(void)hideProgressView{
    [self.progessView.superview removeFromSuperview];
    self.progessView = nil;
}

#pragma mark - copy video data out of photo album
//notified when the videoAssetToTempFile success block is run
-(void)finishedMovingVideoForAsset:(ALAsset*)asset withURL:(NSURL*)fileURL{
    //    [self.videoQueue removeObject:asset];
    [self processAsset:asset withURL:fileURL];
}

//notified when the videoAssetToTempFile failure block is run
-(void)failedMovingVideoForAsset:(ALAsset*)asset{
    NSLog(@"<ELCImagePickerController> Failed to move video file to tmp; removing from queue ");
//    [self.videoQueue removeObject:asset];
    self.processCount--;
    [self assetProcessed];
}

//caches the video file data to the tmp directory then calls the next step when processed
-(void) videoAssetToTempFile:(ALAsset*)asset
{    
    NSURL *url = [[asset valueForProperty:ALAssetPropertyURLs] valueForKey:[[[asset valueForProperty:ALAssetPropertyURLs] allKeys] objectAtIndex:0]];
//    NSString * surl = [url absoluteString];
//    NSString * ext = [surl substringFromIndex:[surl rangeOfString:@"ext="].location + 4];
//    NSTimeInterval ti = [[NSDate date]timeIntervalSinceReferenceDate];
//    NSString * filename = [NSString stringWithFormat: @"%f.%@",ti,ext];
    NSString * tmpfile = [self tmpPathForAssetURL:url];
    //[NSTemporaryDirectory() stringByAppendingPathComponent:filename];

    ALAssetsLibraryAssetForURLResultBlock resultblock = ^(ALAsset *myasset)
    {
        
        ALAssetRepresentation * rep = [myasset defaultRepresentation];
        
        NSUInteger size = [rep size];
        const int bufferSize = 8192;
        
//        NSLog(@"Writing to %@",tmpfile);
        FILE* f = fopen([tmpfile cStringUsingEncoding:1], "wb+");
        if (f == NULL) {
            NSLog(@"Can not create tmp file.");
            return;
        }
        
        Byte * buffer = (Byte*)malloc(bufferSize);
        int read = 0, offset = 0, written = 0;
        NSError* err;
        if (size != 0) {
            do {
                read = [rep getBytes:buffer
                          fromOffset:offset
                              length:bufferSize
                               error:&err];
                written = fwrite(buffer, sizeof(char), read, f);
                offset += read;
            } while (read != 0);
            
            
        }
        fclose(f);
        [self finishedMovingVideoForAsset:asset withURL:[NSURL fileURLWithPath:tmpfile]];
    };
    
    
    ALAssetsLibraryAccessFailureBlock failureblock  = ^(NSError *myerror)
    {
        NSLog(@"Can not get asset - %@",[myerror localizedDescription]);
        [self failedMovingVideoForAsset:asset];
    };
    
    if(url)
    {
        ALAssetsLibrary* assetslibrary = [[[ALAssetsLibrary alloc] init] autorelease];
        [assetslibrary assetForURL:url
                       resultBlock:resultblock
                      failureBlock:failureblock];
    }
    
//    return [NSURL fileURLWithPath:tmpfile];
}



#pragma mark - rotation
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return YES;
    } else {
        return toInterfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
    }
}

#pragma mark -
#pragma mark Memory management

- (void)didReceiveMemoryWarning
{
    NSLog(@"ELC Image Picker received memory warning.");
    
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload {
    [super viewDidUnload];
}


- (void)dealloc
{
    NSLog(@"deallocing ELCImagePickerController");
    [_videoQueue release];
    [_processedAssets release];
    [_imageQueue release];
//    [_myDelegate release];
    
    _videoQueue = nil;
    _processedAssets = nil;
    _imageQueue = nil;
    _myDelegate = nil;
    
    [super dealloc];
}

@end
