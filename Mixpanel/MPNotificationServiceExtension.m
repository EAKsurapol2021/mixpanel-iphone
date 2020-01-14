#import "MPNotificationServiceExtension.h"
#import "MPLogger.h"

static NSString *const dynamicCategoryIdentifier = @"MP_DYNAMIC";
static NSString *const mediaUrlKey = @"mp_media_url";

API_AVAILABLE(ios(10.0))
@interface MPNotificationServiceExtension()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *notificationContent;
@property BOOL richContentTaskComplete;
@property BOOL notificationCategoriesTaskComplete;

@end

@implementation MPNotificationServiceExtension

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent *_Nonnull))contentHandler  {
    
    self.contentHandler = contentHandler;
    self.notificationContent = [request.content mutableCopy];
    
    NSDictionary *userInfo = request.content.userInfo;
    if (userInfo == nil) {
        [self sendContent];
        return;
    }
    
    NSArray* buttons = userInfo[@"mp_buttons"];
    if (buttons) {
        [self registerDynamicCategory:userInfo withButtons:buttons];
    } else {
#ifdef DEBUG
        MPLogInfo(@"%@ No action buttons specified, not adding dynamic category", self);
#endif
    }

    NSString *mediaUrl = userInfo[mediaUrlKey];
    if (mediaUrl) {
        [self attachRichMedia:userInfo withMediaUrl:mediaUrl];
    } else {
#ifdef DEBUG
        MPLogInfo(@"%@ No media url specified, not attatching rich media", self);
#endif
    }
}

- (void)serviceExtensionTimeWillExpire {
    [self sendContent];
}

- (void)taskComplete {
    if (self.richContentTaskComplete && self.notificationCategoriesTaskComplete) {
        [self sendContent];
    }
}

- (void)sendContent {
    self.contentHandler(self.notificationContent);
}

- (void)registerDynamicCategory:(NSDictionary *) userInfo withButtons:(NSArray *) buttons {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationCategoriesWithCompletionHandler:^(NSSet<UNNotificationCategory *> *_Nonnull categories) {
        
        NSSet<UNNotificationCategory *> *filteredCategories = [categories objectsPassingTest:^BOOL(UNNotificationCategory *_Nonnull category, BOOL *_Nonnull stop) {
            return ![[category identifier] containsString:dynamicCategoryIdentifier];
        }];

       __block NSArray* actions = @[];
        [buttons enumerateObjectsUsingBlock:^(NSDictionary *button, NSUInteger idx, BOOL *_Nonnull stop) {
            UNNotificationAction* action = [UNNotificationAction
                                            actionWithIdentifier:[NSString stringWithFormat:@"MP_ACTION_%lu", (unsigned long)idx]
                       title:button[@"lbl"]
                       options:UNNotificationActionOptionForeground];
            actions = [actions arrayByAddingObject:action];
        }];

        UNNotificationCategory* mpDynamicCategory = [UNNotificationCategory
            categoryWithIdentifier:dynamicCategoryIdentifier
            actions:actions
            intentIdentifiers:@[]
            options:UNNotificationCategoryOptionNone];
        
        NSSet<UNNotificationCategory *>* finalCategory = [filteredCategories setByAddingObject:mpDynamicCategory];
        
        [center setNotificationCategories:finalCategory];
        
        self.notificationCategoriesTaskComplete = true;
        
        [self taskComplete];
    }];
}

- (void)attachRichMedia:(NSDictionary *) userInfo withMediaUrl:(NSString *) mediaUrl {
    NSString *mediaType = [mediaUrl pathExtension];
    
    if (mediaUrl == nil || mediaType == nil) {
        if (mediaUrl == nil) {
            MPLogInfo(@"%@ unable to add attachment: %@ is nil", self, mediaUrlKey);
        }
        
        if (mediaType == nil) {
            MPLogInfo(@"%@ unable to add attachment: extension is nil", self);
        }
        self.richContentTaskComplete = true;
        [self taskComplete];
        return;
    }
    
    // load the attachment
    [self loadAttachmentForUrlString:mediaUrl
                            withType:mediaType
                   completionHandler:^(UNNotificationAttachment *attachment) {
                        if (attachment) {
                            self.notificationContent.attachments = [NSArray arrayWithObject:attachment];
                        }
                        self.richContentTaskComplete = true;
                        [self taskComplete];
                   }];
}
- (void)loadAttachmentForUrlString:(NSString *)urlString withType:(NSString *)type
                 completionHandler:(void(^)(UNNotificationAttachment *))completionHandler  {
    __block UNNotificationAttachment *attachment = nil;
    NSURL *attachmentURL = [NSURL URLWithString:urlString];
    NSString *fileExt = [@"." stringByAppendingString:type];
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    [[session downloadTaskWithURL:attachmentURL
                completionHandler:^(NSURL *temporaryFileLocation, NSURLResponse *response, NSError *error) {
                    if (error != nil) {
                        MPLogInfo(@"%@ unable to add attachment: %@", self, error.localizedDescription);
                    } else {
                        NSFileManager *fileManager = [NSFileManager defaultManager];
                        NSURL *localURL = [NSURL fileURLWithPath:[temporaryFileLocation.path stringByAppendingString:fileExt]];
                        [fileManager moveItemAtURL:temporaryFileLocation toURL:localURL error:&error];
                        
                        NSError *attachmentError = nil;
                        attachment = [UNNotificationAttachment attachmentWithIdentifier:@"" URL:localURL options:nil error:&attachmentError];
                        if (attachmentError || !attachment) {
                            MPLogInfo(@"%@ unable to add attchment: %@", self, attachmentError.localizedDescription);
                        }
                    }
                    completionHandler(attachment);
                }] resume];
}

@end
