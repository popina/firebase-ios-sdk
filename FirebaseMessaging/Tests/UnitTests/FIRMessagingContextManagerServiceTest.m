/*
 * Copyright 2017 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0 ||                                          \
    __MAC_OS_X_VERSION_MAX_ALLOWED >= __MAC_10_14 || __TV_OS_VERSION_MAX_ALLOWED >= __TV_10_0 || \
    __WATCH_OS_VERSION_MAX_ALLOWED >= __WATCHOS_3_0 || TARGET_OS_MACCATALYST
#import <UserNotifications/UserNotifications.h>
#endif
#import <XCTest/XCTest.h>
#import "OCMock.h"

#import "FirebaseMessaging/Sources/FIRMessagingContextManagerService.h"

static NSString *const kBody = @"Save 20% off!";
static NSString *const kUserInfoKey1 = @"level";
static NSString *const kUserInfoKey2 = @"isPayUser";
static NSString *const kUserInfoValue1 = @"5";
static NSString *const kUserInfoValue2 = @"Yes";
static NSString *const kMessageIdentifierKey = @"gcm.message_id";
static NSString *const kMessageIdentifierValue = @"1584748495200141";

API_AVAILABLE(macos(10.14))
@interface FIRMessagingContextManagerServiceTest : XCTestCase

@property(nonatomic, readwrite, strong) NSDateFormatter *dateFormatter;
@property(nonatomic, readwrite, strong) NSMutableArray *scheduledLocalNotifications;
@property(nonatomic, readwrite, strong)
    NSMutableArray<UNNotificationRequest *> *requests API_AVAILABLE(ios(10.0), macos(10.4));

@end

@implementation FIRMessagingContextManagerServiceTest

- (void)setUp {
  [super setUp];
  self.dateFormatter = [[NSDateFormatter alloc] init];
  self.dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
  self.scheduledLocalNotifications = [[NSMutableArray alloc] init];
  if (@available(macOS 10.14, iOS 10.0, watchOS 3.0, tvOS 10.0, *)) {
    self.requests = [[NSMutableArray alloc] init];
  }

  [self mockSchedulingLocalNotifications];
}

- (void)tearDown {
  [super tearDown];
}

/**
 *  Test invalid context manager message, missing lt_start string.
 */
- (void)testInvalidContextManagerMessage_missingStartTime {
  NSDictionary *message = @{
    @"hello" : @"world",
  };
  XCTAssertFalse([FIRMessagingContextManagerService isContextManagerMessage:message]);
}

/**
 *  Test valid context manager message.
 */
- (void)testValidContextManagerMessage {
  NSDictionary *message = @{
    kFIRMessagingContextManagerLocalTimeStart : @"2015-12-12 00:00:00",
    @"hello" : @"world",
  };
  XCTAssertTrue([FIRMessagingContextManagerService isContextManagerMessage:message]);
}

/**
 *  Context Manager message with future start date should be successfully scheduled.
 */
- (void)testMessageWithFutureStartTime {
  // way into the future
  NSString *startTimeString = [self.dateFormatter stringFromDate:[NSDate distantFuture]];
  NSDictionary *message = @{
    kFIRMessagingContextManagerLocalTimeStart : startTimeString,
    kFIRMessagingContextManagerBodyKey : kBody,
    kMessageIdentifierKey : kMessageIdentifierValue,
    kUserInfoKey1 : kUserInfoValue1,
    kUserInfoKey2 : kUserInfoValue2
  };
  XCTAssertTrue([FIRMessagingContextManagerService handleContextManagerMessage:message]);

  if (@available(macOS 10.14, iOS 10.0, watchOS 3.0, tvOS 10.0, *)) {
    XCTAssertEqual(self.requests.count, 1);
    UNNotificationRequest *request = self.requests.firstObject;
    XCTAssertEqualObjects(request.identifier, kMessageIdentifierValue);
#if TARGET_OS_IOS || TARGET_OS_WATCH || TARGET_OS_OSX
    XCTAssertEqualObjects(request.content.body, kBody);
    XCTAssertEqualObjects(request.content.userInfo[kUserInfoKey1], kUserInfoValue1);
    XCTAssertEqualObjects(request.content.userInfo[kUserInfoKey2], kUserInfoValue2);
#endif
    return;
  }

#if TARGET_OS_IOS
  XCTAssertEqual(self.scheduledLocalNotifications.count, 1);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  UILocalNotification *notification = self.scheduledLocalNotifications.firstObject;
#pragma clang diagnostic pop
  NSDate *date = [self.dateFormatter dateFromString:startTimeString];
  XCTAssertEqual([notification.fireDate compare:date], NSOrderedSame);
  XCTAssertEqualObjects(notification.alertBody, kBody);
  XCTAssertEqualObjects(notification.userInfo[kUserInfoKey1], kUserInfoValue1);
  XCTAssertEqualObjects(notification.userInfo[kUserInfoKey2], kUserInfoValue2);
#endif
}

/**
 *  Context Manager message with past end date should not be scheduled.
 */
- (void)testMessageWithPastEndTime {
#if TARGET_OS_IOS
  NSString *startTimeString = @"2010-01-12 12:00:00";  // way into the past
  NSString *endTimeString = @"2011-01-12 12:00:00";    // way into the past
  NSDictionary *message = @{
    kFIRMessagingContextManagerLocalTimeStart : startTimeString,
    kFIRMessagingContextManagerLocalTimeEnd : endTimeString,
    kFIRMessagingContextManagerBodyKey : kBody,
    kMessageIdentifierKey : kMessageIdentifierValue,
    @"hello" : @"world"
  };

  XCTAssertTrue([FIRMessagingContextManagerService handleContextManagerMessage:message]);
  if (@available(macOS 10.14, iOS 10.0, watchOS 3.0, tvOS 10.0, *)) {
    XCTAssertEqual(self.requests.count, 0);
    return;
  }
  XCTAssertEqual(self.scheduledLocalNotifications.count, 0);
#endif
}

/**
 *  Context Manager message with past start and future end date should be successfully
 *  scheduled.
 */
- (void)testMessageWithPastStartAndFutureEndTime {
#if TARGET_OS_IOS
  NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:-1000];  // past
  NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow:1000];     // future
  NSString *startTimeString = [self.dateFormatter stringFromDate:startDate];
  NSString *endTimeString = [self.dateFormatter stringFromDate:endDate];

  NSDictionary *message = @{
    kFIRMessagingContextManagerLocalTimeStart : startTimeString,
    kFIRMessagingContextManagerLocalTimeEnd : endTimeString,
    kFIRMessagingContextManagerBodyKey : kBody,
    kMessageIdentifierKey : kMessageIdentifierValue,
    kUserInfoKey1 : kUserInfoValue1,
    kUserInfoKey2 : kUserInfoValue2
  };

  XCTAssertTrue([FIRMessagingContextManagerService handleContextManagerMessage:message]);

  if (@available(macOS 10.14, iOS 10.0, watchOS 3.0, tvOS 10.0, *)) {
    XCTAssertEqual(self.requests.count, 1);
    UNNotificationRequest *request = self.requests.firstObject;
    XCTAssertEqualObjects(request.identifier, kMessageIdentifierValue);
    XCTAssertEqualObjects(request.content.body, kBody);
    XCTAssertEqualObjects(request.content.userInfo[kUserInfoKey1], kUserInfoValue1);
    XCTAssertEqualObjects(request.content.userInfo[kUserInfoKey2], kUserInfoValue2);
    return;
  }
  XCTAssertEqual(self.scheduledLocalNotifications.count, 1);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  UILocalNotification *notification = [self.scheduledLocalNotifications firstObject];
#pragma clang diagnostic pop
  // schedule notification after start date
  XCTAssertEqual([notification.fireDate compare:startDate], NSOrderedDescending);
  // schedule notification after end date
  XCTAssertEqual([notification.fireDate compare:endDate], NSOrderedAscending);
  XCTAssertEqualObjects(notification.userInfo[kUserInfoKey1], kUserInfoValue1);
  XCTAssertEqualObjects(notification.userInfo[kUserInfoKey2], kUserInfoValue2);
#endif
}

/**
 *  Test correctly parsing user data in local notifications.
 */
- (void)testTimedNotificationsUserInfo {
#if TARGET_OS_IOS
  // way into the future
  NSString *startTimeString = [self.dateFormatter stringFromDate:[NSDate distantFuture]];

  NSDictionary *message = @{
    kFIRMessagingContextManagerLocalTimeStart : startTimeString,
    kFIRMessagingContextManagerBodyKey : kBody,
    kMessageIdentifierKey : kMessageIdentifierValue,
    kUserInfoKey1 : kUserInfoValue1,
    kUserInfoKey2 : kUserInfoValue2
  };

  XCTAssertTrue([FIRMessagingContextManagerService handleContextManagerMessage:message]);
  if (@available(macOS 10.14, iOS 10.0, watchOS 3.0, tvOS 10.0, *)) {
    XCTAssertEqual(self.requests.count, 1);
    UNNotificationRequest *request = self.requests.firstObject;
    XCTAssertEqualObjects(request.identifier, kMessageIdentifierValue);
    XCTAssertEqualObjects(request.content.body, kBody);
    XCTAssertEqualObjects(request.content.userInfo[kUserInfoKey1], kUserInfoValue1);
    XCTAssertEqualObjects(request.content.userInfo[kUserInfoKey2], kUserInfoValue2);
    return;
  }
  XCTAssertEqual(self.scheduledLocalNotifications.count, 1);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  UILocalNotification *notification = [self.scheduledLocalNotifications firstObject];
#pragma clang diagnostic pop
  XCTAssertEqualObjects(notification.userInfo[kUserInfoKey1], kUserInfoValue1);
  XCTAssertEqualObjects(notification.userInfo[kUserInfoKey2], kUserInfoValue2);
#endif
}

#pragma mark - Private Helpers

- (void)mockSchedulingLocalNotifications {
  if (@available(macOS 10.14, iOS 10.0, watchOS 3.0, tvOS 10.0, *)) {
    id mockNotificationCenter =
        OCMPartialMock([UNUserNotificationCenter currentNotificationCenter]);
    __block UNNotificationRequest *request;
    [[[mockNotificationCenter stub] andDo:^(NSInvocation *invocation) {
      [self.requests addObject:request];
    }] addNotificationRequest:[OCMArg checkWithBlock:^BOOL(id obj) {
         if ([obj isKindOfClass:[UNNotificationRequest class]]) {
           request = obj;
           [self.requests addObject:request];
           return YES;
         }
         return NO;
       }]
        withCompletionHandler:^(NSError *_Nullable error){
        }];
    return;
  }
#if TARGET_OS_IOS
  id mockApplication = OCMPartialMock([UIApplication sharedApplication]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  __block UILocalNotification *notificationToSchedule;
  [[[mockApplication stub] andDo:^(NSInvocation *invocation) {
    // Mock scheduling a notification
    if (notificationToSchedule) {
      [self.scheduledLocalNotifications addObject:notificationToSchedule];
    }
  }] scheduleLocalNotification:[OCMArg checkWithBlock:^BOOL(id obj) {
       if ([obj isKindOfClass:[UILocalNotification class]]) {
         notificationToSchedule = obj;
         return YES;
       }
       return NO;
     }]];
#pragma clang diagnostic pop
#endif
}

@end
