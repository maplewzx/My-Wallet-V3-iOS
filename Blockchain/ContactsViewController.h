//
//  ContactsViewController.h
//  Blockchain
//
//  Created by Kevin Wu on 11/1/16.
//  Copyright © 2016 Blockchain Luxembourg S.A. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ContactsViewController : UIViewController
- (void)didCreateInvitation:(NSDictionary *)invitationDict;
- (void)didReadInvitation:(NSDictionary *)invitation identifier:(NSString *)identifier;
- (void)didAcceptInvitation:(NSDictionary *)invitation name:(NSString *)name;
- (void)didReadInvitationSent;

// Messages Controller
- (void)didGetMessages;
- (void)didReadMessage:(NSString *)message;
- (void)didSendMessage:(NSString *)contact;

// Detail Controller
- (void)didChangeTrust;
- (void)didFetchExtendedPublicKey;
@end
