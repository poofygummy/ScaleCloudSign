//
//  ALTAppGroup.h
//  ScaleCloudSign
//
//  Created by Riley Testut on 6/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTAppGroup : NSObject

@property (copy, nonatomic, readonly) NSString *name;
@property (copy, nonatomic, readonly) NSString *identifier;

@property (copy, nonatomic, readonly) NSString *groupIdentifier;

@end

NS_ASSUME_NONNULL_END
