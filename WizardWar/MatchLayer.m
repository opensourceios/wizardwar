//
//  MatchLayer.m
//  WizardWar
//
//  Created by Sean Hess on 5/17/13.
//  Copyright (c) 2013 The LAB. All rights reserved.
//

#import "MatchLayer.h"
#import "cocos2d.h"
#import "MatchGroundSprite.h"
#import "WizardSprite.h"
#import "Match.h"
#import "Spell.h"
#import "SpellSprite.h"
#import "NSArray+Functional.h"
#import "NSArray+Functional.h"
#import "Elements.h"
#import "SimpleAudioEngine.h"

#import "SpellFireball.h"
#import "SpellEarthwall.h"
#import "SpellBubble.h"
#import "SpellMonster.h"
#import "SpellVine.h"
#import "SpellWindblast.h"
#import "SpellIcewall.h"
#import "NSArray+Functional.h"
#import "LifeManaIndicatorNode.h"

@interface MatchLayer () <CCTouchOneByOneDelegate, MatchDelegate, PentagramDelegate>
@property (nonatomic, strong) Match * match;
@property (nonatomic, strong) Units * units;
@property (nonatomic, strong) NSMutableArray * spellSprites;

@property (nonatomic, strong) NSString * matchId;

@property (nonatomic, strong) CCSprite * message;
@property (nonatomic, strong) CCSprite * background;

@property (nonatomic, strong) UIButton * backButton;

@property (nonatomic, strong) LifeManaIndicatorNode *player1Indicator;
@property (nonatomic, strong) LifeManaIndicatorNode *player2Indicator;

@end

@implementation MatchLayer

-(id)initWithMatchId:(NSString*)matchId player:(Player *)player withAI:(Player *)ai {
    if ((self = [super init])) {
        self.matchId = matchId;
        NSLog(@"PLAYER NAME %@", player.name);
        
        // background
        self.background = [CCSprite spriteWithFile:@"background-cave.png"];
        self.background.anchorPoint = ccp(0,0);
        [self addChild:self.background];
        
        // preload bg music
        SimpleAudioEngine *sae = [SimpleAudioEngine sharedEngine];
        if (sae != nil) {
            [sae preloadBackgroundMusic:@"theme.wav"];
            if (sae.willPlayBackgroundMusic) {
                sae.backgroundMusicVolume = 0.4f;
            }
        }
        
        [sae playBackgroundMusic:@"theme.wav"];

        // Lets try and overlay some UIKit stuff for the pentagram!
        UIView *openGlView = [[CCDirector sharedDirector] view];
        self.pentagramViewController = [[PentagramViewController alloc] init];
        self.pentagramViewController.view.backgroundColor = [UIColor clearColor];
        CGRect frame = openGlView.frame;
        frame.size.width = 246;
        frame.origin.x = (openGlView.frame.size.width - frame.size.width)/2;
        self.pentagramViewController.view.frame = frame;
        self.pentagramViewController.view.opaque = NO;
        self.pentagramViewController.delegate = self;
        [openGlView addSubview:self.pentagramViewController.view];
        [openGlView bringSubviewToFront:self.pentagramViewController.view];
        
        // I need to join. Am I 1st player or 2nd player?
        // Hmm... I need to know
        
        [[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:0 swallowsTouches:NO];
        
        self.match = [[Match alloc] initWithId:self.matchId currentPlayer:player withAI:ai];
        self.match.delegate = self;
        
        self.spellSprites = [NSMutableArray array];
        
        CGFloat zeroY = 100;
        CGFloat wizardOffset = 75;
        self.units = [[Units alloc] initWithZeroY:zeroY min:wizardOffset max:self.contentSize.width-wizardOffset];
        
//        self.label = [CCLabelTTF labelWithString:@"Ready" fontName:@"Marker Felt" fontSize:36];
//        self.label.position = ccp(self.contentSize.width/2, self.contentSize.height/2);
//        [self addChild:self.label];
        
        [[CCSpriteFrameCache sharedSpriteFrameCache] addSpriteFramesWithFile:@"messages.plist"];
        
        self.message = [[CCSprite alloc] initWithSpriteFrameName:@"msg-ready.png"];
        self.message.position = ccp(self.contentSize.width/2, self.contentSize.height/2);
        [self addChild:self.message];
        
        self.player1Indicator = [LifeManaIndicatorNode node];
        self.player2Indicator = [LifeManaIndicatorNode node];
        
        self.player2Indicator.position = ccp(openGlView.frame.size.width - 150, 290);
        self.player1Indicator.position = ccp(150, 290);
        
        [self addChild:self.player1Indicator];
        [self addChild:self.player2Indicator];
        
        [self scheduleUpdate];
        
        // BACK BUTTON
        self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.backButton setImage:[UIImage imageNamed:@"exit.png"] forState:UIControlStateNormal];
        self.backButton.frame = CGRectMake(8, 8, 28, 22);
        [self.backButton addTarget:self action:@selector(didTapBack:) forControlEvents:UIControlEventTouchUpInside];
        [openGlView addSubview:self.backButton];
    }
    return self;
}

- (void)onExit {
    [[[CCDirector sharedDirector] touchDispatcher] removeDelegate:self];
}

-(void)update:(ccTime)delta {
    //    NSLog(@"Updated %f", delta);
    
    // need to update each one
    [self.match update:delta];
}

#pragma mark -  MATCH DELEGATE

-(void)didRemoveSpell:(Spell *)spell {
    SpellSprite * sprite = [self.spellSprites find:^BOOL(SpellSprite * sprite) {
        return (sprite.spell == spell);
    }];
    [self removeChild:sprite];
}

-(void)didAddSpell:(Spell *)spell {
    SpellSprite * sprite = [[SpellSprite alloc] initWithSpell:spell units:self.units];
    [self addChild:sprite];
    [self.spellSprites addObject:sprite];
}

-(void)matchStarted {
    self.message.visible = NO;
    self.pentagramViewController.view.hidden = NO;
    [self.match.players forEach:^(Player*player) {
        CCSprite * wizard = [[WizardSprite alloc] initWithPlayer:player units:self.units];
        [self addChild:wizard];
    }];
    
    self.player1Indicator.player = self.match.players[0];
    self.player2Indicator.player = self.match.players[1];
}

-(void)matchEnded {
    
    self.pentagramViewController.view.hidden = YES;
    if (self.match.currentPlayer.state == PlayerStateDead){
        [self.message setDisplayFrame:[[CCSpriteFrameCache sharedSpriteFrameCache] spriteFrameByName:@"msg-you-lose.png"]];
        
    } else {
        [self.message setDisplayFrame:[[CCSpriteFrameCache sharedSpriteFrameCache] spriteFrameByName:@"msg-you-won.png"]];
    }
    self.message.visible = YES;
}

-(void)didUpdateHealthAndMana
{
    [self.player1Indicator updateFromPlayer];
    [self.player2Indicator updateFromPlayer];
}

-(void)drawWizard:(Player*)player {
    
}

-(void)didTapBack:(id)sender {
    [self.delegate doneWithMatch];
}


// TOUCHES

-(BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    return YES;
}

-(void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
    
}

-(void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    
//    CGPoint touchPoint = [touch locationInView:touch.view];
    
    /*if (!self.match.started) {
        
        if (self.match.loser) {
            NSLog(@"OVER");
            [self.delegate doneWithMatch];
        }
        else {
            NSLog(@"NOT STARTED");
        }
        return;
    }
    
    CGPoint touchPoint = [touch locationInView:touch.view];
    CGSize winSize = [[CCDirector sharedDirector] winSize];
    
    // add the spell here
    Spell * spell = nil;
    if (touchPoint.x < winSize.width/2)
        spell = [SpellEarthwall new];
    else
        spell = [SpellFireball new];
    
    [self.match castSpell:spell];
    [spell setPositionFromPlayer:self.match.currentPlayer];
    
    [self.match addSpell:spell]; // add spell
    NSLog(@"NEW SPELL! %@", spell);*/
}

# pragma mark Pentagram Delegate

-(void)didSelectElement:(NSArray *)elements
{
//    NSLog(@"selected element %@", elements);
}

-(void)didCastSpell:(NSArray *)elements
{
    NSString * comboId = [Elements comboId:elements];
    NSLog(@"cast spell %@", comboId);
    
    Spell * spell = nil;
    
    if ([comboId isEqualToString:@"FAF"]) {
        spell = [SpellFireball new];
        [[SimpleAudioEngine sharedEngine] playEffect:@"fireball.wav"];
    }
    
    else if ([comboId isEqualToString:@"EWE"]) {
        spell = [SpellEarthwall new];
        [[SimpleAudioEngine sharedEngine] playEffect:@"earthwall.wav"];
    }
    
    else if ([comboId isEqualToString:@"AHW"]) {
        spell = [SpellWindblast new];
    }
    
    else if ([comboId isEqualToString:@"EFHW"]) {
        spell = [SpellMonster new];
    }
    
    else if ([comboId isEqualToString:@"WAE"]) {
        spell = [SpellIcewall new];
    }
    
    else if ([comboId isEqualToString:@"WAH"]) {
        spell = [SpellBubble new];
    }
    
    else if ([comboId isEqualToString:@"WAEH"]) {
        spell = [SpellVine new];
    }
    
    else if ([comboId isEqualToString:@"EFAWH"]) {
        spell = nil;
        NSLog(@"CAPTIAN PLANET");
    }
    
    if (spell != nil) {
        [self.match castSpell:spell];
    }
}


@end
