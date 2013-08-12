//
//  MatchmakingViewController.m
//  WizardWar
//
//  Created by Sean Hess on 5/17/13.
//  Copyright (c) 2013 The LAB. All rights reserved.
//

// This is such a crappy way of doing all of this
// I need another approach.
// CoreData? -- would be a good idea

// How to do distance?
// Hmm..... Well, I have the location and userId of each one
// I just have to evaluate distance and keep track of ones that are close!

#import "MatchmakingViewController.h"
#import "WizardDirector.h"
#import "MatchLayer.h"
#import "Challenge.h"
#import "NSArray+Functional.h"
#import "FirebaseCollection.h"
#import "ConnectionService.h"
#import "MatchViewController.h"
#import "User.h"
#import "LobbyService.h"
#import "UserService.h"
#import "ChallengeService.h"
#import "LocationService.h"
#import "UserFriendService.h"
#import <ReactiveCocoa.h>
#import "ComicZineDoubleLabel.h"
#import "ObjectStore.h"
#import "UserCell.h"
#import "ChallengeCell.h"
#import "FriendsViewController.h"
#import <BButton.h>
#import "SettingsViewController.h"
#import <NSString+FontAwesome.h>
#import <FacebookSDK/FacebookSDK.h>
#import "AnalyticsService.h"
#import "UIViewController+Idiom.h"

#define SECTION_INDEX_CHALLENGES 0

// People who are "Right here" but who aren't friends. Usually this will be blank
#define SECTION_INDEX_LOCAL 1

// Friends who are online
#define SECTION_INDEX_FRIENDS_ONLINE 2

// People who are closeby, but not RIGHT here
#define SECTION_INDEX_CLOSE 3

// Offline friends
#define SECTION_INDEX_FRIENDS 4

#define SECTION_INDEX_STRANGERS 5

#define SECTION_INDEX_ONLINE_USERS SECTION_INDEX_LOCAL
#define SECTION_INDEX_OFFLINE_USERS SECTION_INDEX_FRIENDS
#define SECTION_INDEX_LAST SECTION_INDEX_FRIENDS

#define SECTION_INDEX_MESSAGES 0


@interface MatchmakingViewController () <NSFetchedResultsControllerDelegate, FBFriendPickerDelegate, MatchViewControllerDelegate>
@property (nonatomic, weak) IBOutlet UITableView * tableView;

@property (nonatomic, strong) ConnectionService* connection;

@property (nonatomic, readonly) User * currentUser;
@property (strong, nonatomic) MatchLayer * match;

@property (strong, nonatomic) NSFetchedResultsController * challengeResults;
@property (strong, nonatomic) NSFetchedResultsController * friendResults;
@property (strong, nonatomic) NSFetchedResultsController * localResults;
@property (strong, nonatomic) NSFetchedResultsController * otherCloseResults;
@property (strong, nonatomic) NSFetchedResultsController * friendOnlineResults;
@property (strong, nonatomic) NSFetchedResultsController * allResults;

@property (strong, nonatomic) RACDisposable * matchStatusSignal;

@property (strong, nonatomic) IBOutlet UITextView *warningsView;
@property (strong, nonatomic) IBOutlet UITextView *explanationsView;

@property (weak, nonatomic) IBOutlet UIView *loadingOverlayView;

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityView;

@property (weak, nonatomic) IBOutlet BButton *inviteFriendsButton;

@property (strong, nonatomic) MatchViewController * currentMatch;
@property (strong, nonatomic) Challenge * currentChallenge;

@property (nonatomic) BOOL connectedToLobby;

@end

@implementation MatchmakingViewController

- (void)viewDidLoad
{
    [AnalyticsService event:@"MatchmakingLoad"];
    
    [super viewDidLoad];

    [self.inviteFriendsButton addAwesomeIcon:FAIconFacebookSign beforeTitle:YES];
    [self.inviteFriendsButton setType:BButtonTypeFacebook];
//    [self.inviteFriendsButton.titleLabel.font = [UIFont fontWithName:@"FontAwesome" size:26];

    UIBarButtonItem *accountButton = [[UIBarButtonItem alloc] initWithTitle:[NSString stringFromAwesomeIcon:FAIconUser] style:UIBarButtonItemStylePlain target:self action:@selector(didTapAccount)];
    
    [accountButton setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIFont fontWithName:@"FontAwesome" size:20.0], UITextAttributeFont, nil] forState:UIControlStateNormal];
    self.navigationItem.rightBarButtonItem = accountButton;
    
    // Custom Table Cells!
    [self.tableView registerNib:[UINib nibWithNibName:@"UserCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"UserCell"];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"ChallengeCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"ChallengeCell"];
    
    [self.tableView setTableFooterView:self.explanationsView];
    
    self.title = @"Matchmaking";
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    self.navigationItem.titleView = [ComicZineDoubleLabel titleView:self.title navigationBar:self.navigationController.navigationBar];

    __weak MatchmakingViewController * wself = self;
    
    // LOBBY
    [RACAble(LobbyService.shared, joined) subscribeNext:^(id x) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [wself didUpdateJoinedLobby:LobbyService.shared.joined];
        });
    }];
    [wself didUpdateJoinedLobby:LobbyService.shared.joined];
    
    
    [RACAble(LocationService.shared, accepted) subscribeNext:^(id x) {
        [self.tableView reloadData];
    }];
    
    [RACAble(UserService.shared, pushAccepted) subscribeNext:^(id x) {
        [self.tableView reloadData];
    }];
    
    
    
    // CHECK AUTHENTICATED
//    if ([UserService shared].isAuthenticated) {
        [self connect];
//    }
//    else {
//        AccountViewController * accounts = [AccountViewController new];
//        accounts.delegate = self;
//        [self.navigationController presentViewController:accounts animated:YES completion:nil];
//    }
}

- (void)connect {
    NSError *error = nil;
    
    User * user = [UserService.shared currentUser];
    NSLog(@"MatchmakingViewController: connect");
    
    self.challengeResults = [ObjectStore.shared fetchedResultsForRequest:[ChallengeService.shared requestChallengesForUser:self.currentUser]];
    self.challengeResults.delegate = self;
    [self.challengeResults performFetch:&error];
    
    self.friendResults = [ObjectStore.shared fetchedResultsForRequest:[UserFriendService.shared requestFriends:user isOnline:NO]];
    self.friendResults.delegate = self;
    [self.friendResults performFetch:&error];
    
    self.friendOnlineResults = [ObjectStore.shared fetchedResultsForRequest:[UserFriendService.shared requestFriends:user isOnline:YES]];
    self.friendOnlineResults.delegate = self;
    [self.friendOnlineResults performFetch:&error];
    
    // Show anyone right here, and 4 closest other users online
    self.localResults = [ObjectStore.shared fetchedResultsForRequest:[LobbyService.shared requestCloseUsers:self.currentUser]];
    self.localResults.delegate = self;
    [self.localResults performFetch:&error];
    
    self.otherCloseResults = [ObjectStore.shared fetchedResultsForRequest:[LobbyService.shared requestClosestUsers:self.currentUser withLimit:4]];
    self.otherCloseResults.delegate = self;
    [self.otherCloseResults performFetch:&error];
    
    
    // DEBUG ONLY: show all users. Uncomment and change # of sections to 4
//    self.allResults = [ObjectStore.shared fetchedResultsForRequest:[UserFriendService.shared requestStrangers:user withLimit:5]];
//    self.allResults.delegate = self;
//    [self.allResults performFetch:&error];
    

    // I think friends should be showing up faster, no?
    [self.tableView reloadData];
    
    [ChallengeService.shared connectAndReset];
    [LocationService.shared startMonitoring];

//    __weak MatchmakingViewController * wself = self;

    
    // Join the lobby!
    [LobbyService.shared joinLobby:self.currentUser];
}

- (void)viewWillAppear:(BOOL)animated {
    self.currentChallenge = nil;
    self.currentMatch = nil;
    if (ChallengeService.shared.connected) {
        [ChallengeService.shared removeUserChallenge:self.currentUser];
        // Why do this? to remove the challenge you were just in.
        // If the other user leaves
        //[ChallengeService.shared declineAllChallenges:self.currentUser];
        // when the invitee hits back, it's still here for him.
        // need to remove the one I was just in. 
    }
}

- (void)viewDidAppear:(BOOL)animated {

}

- (void)viewWillDisappear:(BOOL)animated {
    
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark NSFetchedResultsControllerDelegate methods


- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath {
    
    NSInteger sectionGlobal = 0;
    if (controller == self.challengeResults) sectionGlobal = SECTION_INDEX_CHALLENGES;
    else if (controller == self.localResults) sectionGlobal = SECTION_INDEX_LOCAL;
    else if (controller == self.otherCloseResults) sectionGlobal = SECTION_INDEX_CLOSE;
    else if (controller == self.friendResults) sectionGlobal = SECTION_INDEX_FRIENDS;
    else if (controller == self.allResults) sectionGlobal = SECTION_INDEX_STRANGERS;
    else if (controller == self.friendOnlineResults) sectionGlobal = SECTION_INDEX_FRIENDS_ONLINE;
    
    NSIndexPath * indexPathGlobal = [NSIndexPath indexPathForItem:indexPath.row inSection:sectionGlobal];
    NSIndexPath * newIndexPathGlobal = [NSIndexPath indexPathForItem:newIndexPath.row inSection:sectionGlobal];
    
    if (type == NSFetchedResultsChangeInsert) {
        if (sectionGlobal == SECTION_INDEX_CHALLENGES) NSLog(@"CHALLENGE INSERT");
        [self.tableView insertRowsAtIndexPaths:@[newIndexPathGlobal] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    else if (type == NSFetchedResultsChangeDelete) {
        if (sectionGlobal == SECTION_INDEX_CHALLENGES) NSLog(@"CHALLENGE DELETE");        
        [self.tableView deleteRowsAtIndexPaths:@[indexPathGlobal] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    else if (type == NSFetchedResultsChangeMove) {
        if (sectionGlobal == SECTION_INDEX_CHALLENGES) {
            NSLog(@"CHALLENGE MOVE");
            return;
        }
        
        // it already knows its user, just reload it
        UserCell * cell = (UserCell*)[self.tableView cellForRowAtIndexPath:indexPathGlobal];
        [cell reloadFromUser];
        [self.tableView moveRowAtIndexPath:indexPathGlobal toIndexPath:newIndexPathGlobal];
    }
    else if (type == NSFetchedResultsChangeUpdate) {
        if (sectionGlobal == SECTION_INDEX_CHALLENGES) {
            NSLog(@"CHALLENGE UPDATE");

            // do a remove/insert instead. it's kewl looking
            [self.tableView deleteRowsAtIndexPaths:@[indexPathGlobal] withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView insertRowsAtIndexPaths:@[newIndexPathGlobal] withRowAnimation:UITableViewRowAnimationAutomatic];
            
            Challenge * challenge = [self.challengeResults objectAtIndexPath:indexPathGlobal];
            if (challenge.status == ChallengeStatusAccepted) {
                [self joinMatch:challenge];
            }

        }
        else {
            UserCell * cell = (UserCell*)[self.tableView cellForRowAtIndexPath:indexPathGlobal];
            [cell reloadFromUser];
        }
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
//    [self.tableView reloadData];
    [self.tableView endUpdates];
}


#pragma mark - Lobby {
-(void)didUpdateJoinedLobby:(BOOL)joined {
    
    if (joined) {
        [self hideLoading];
    }

    else {
        [ChallengeService.shared removeUserChallenge:self.currentUser];

        // If we DISCONNECT, decline all challenges
        // but when you load this for the first, you START disconnected.
        if (self.connectedToLobby == YES)
            [ChallengeService.shared declineAllChallenges:self.currentUser];
        
        [self showLoading];
    }
    
    self.connectedToLobby = joined;
}

-(void)showLoading {
    [self.activityView startAnimating];
    [UIView animateWithDuration:0.2 animations:^{
        self.loadingOverlayView.alpha = 1.0;
    }];    
}

-(void)hideLoading {
    [self.activityView stopAnimating];
    [UIView animateWithDuration:0.2 animations:^{
        self.loadingOverlayView.alpha = 0.0;
    }];
}

#pragma mark - Login

- (IBAction)didTapLogin:(id)sender {
    
}

- (User*)currentUser {
    return UserService.shared.currentUser;
}

#pragma mark - Challenges
-(void)checkAutoconnectChallenge:(Challenge*)challenge {
    if ([challenge.matchId isEqualToString:self.autoconnectToMatchId]) {
        [self joinMatch:challenge];
    }
}



#pragma mark - Table view data source

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SECTION_INDEX_CHALLENGES) return YES;
    return NO;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSIndexPath * localIndexPath = [NSIndexPath indexPathForItem:indexPath.row inSection:0];
        Challenge * challenge = [self.challengeResults objectAtIndexPath:localIndexPath];
        
        // If I created it, then delete it
        if ([ChallengeService.shared challenge:challenge isCreatedByUser:self.currentUser]) {
            [ChallengeService.shared removeChallenge:challenge];
        }
        
        // otherwise decline it
        else {
            [ChallengeService.shared declineChallenge:challenge];
        }
        

    }
}

-(NSString*)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Run Away!";
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return SECTION_INDEX_LAST+1;
//    return 5; // to show debug users
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == SECTION_INDEX_CHALLENGES) {
        return [[self.challengeResults.sections objectAtIndex:0] numberOfObjects];
    } else if (section == SECTION_INDEX_LOCAL){
        return [[self.localResults.sections objectAtIndex:0] numberOfObjects];
    } else if (section == SECTION_INDEX_CLOSE){
        return [[self.otherCloseResults.sections objectAtIndex:0] numberOfObjects];
    } else if (section == SECTION_INDEX_FRIENDS) {
        return [[self.friendResults.sections objectAtIndex:0] numberOfObjects];
    } else if (section == SECTION_INDEX_FRIENDS_ONLINE) {
        return [[self.friendOnlineResults.sections objectAtIndex:0] numberOfObjects];
    } else if (section == SECTION_INDEX_STRANGERS) {
        return [[self.allResults.sections objectAtIndex:0] numberOfObjects];
    } else {
        return 0;
    }
}

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section == SECTION_INDEX_MESSAGES && (!LocationService.shared.accepted || !UserService.shared.pushAccepted)) {
        
        NSMutableString * message = [NSMutableString string];
        
        if (!LocationService.shared.accepted) {
            if (LocationService.shared.cannotFindLocation)
                [message appendString:@"Cannot locate you! Please make sure Location Services are enabled to see players near you.\n"];
            else
                [message appendString:@"Enable Location Services to see players near you. You can do this in Settings.\n"];
        }
        
        if (!UserService.shared.pushAccepted) {
            [message appendString:@"Enable Push Notifications so friends can invite you to play\n"];
        }
        
        self.warningsView.text = message;
        
        return self.warningsView;
    }
    else {
        return nil;
    }
}

//-(CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
//    return 0;
//}

//-(UIView*)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
//    if (section == SECTION_INDEX_LAST) {
//        return self.explanationsView;
//    }
//    return nil;
//}

- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == SECTION_INDEX_CHALLENGES) return @"Challenges";
    
    else if (section == SECTION_INDEX_ONLINE_USERS) return @"Online";
    else if (section == SECTION_INDEX_OFFLINE_USERS) return @"Offline";
    
    else if (section == SECTION_INDEX_CLOSE) return @"Nearby";
    else if (section == SECTION_INDEX_LOCAL) return @"Right Here";
    else if (section == SECTION_INDEX_FRIENDS) return @"Frenemies";
    else if (section == SECTION_INDEX_FRIENDS_ONLINE) return @"Friends Online";
    else if (section == SECTION_INDEX_STRANGERS) return @"Strangers";
    return nil;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == SECTION_INDEX_MESSAGES && (!LocationService.shared.accepted || !UserService.shared.pushAccepted))
        return self.warningsView.frame.size.height;
//    else if (section == SECTION_INDEX_ONLINE_USERS) return 26;
//    else if (section == SECTION_INDEX_OFFLINE_USERS) return 26;
//    else if (section == 1) return 26;
//    else if (section == 2) return 0;
//    else if (section == 3) return 26;
//    else if (section == 4) return 26;
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SECTION_INDEX_CHALLENGES) return 65;
    else return 54;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == SECTION_INDEX_CHALLENGES) {
        return [self tableView:tableView challengeCellForRowAtIndexPath:indexPath];
    } else {
        User * user = [self userForIndexPath:indexPath];
        return [self tableView:tableView userCellForUser:user];
    }
}

-(User*)userForIndexPath:(NSIndexPath*)indexPath {
    NSIndexPath * localIndexPath = [NSIndexPath indexPathForItem:indexPath.row inSection:0];
    User * user = nil;
    if (indexPath.section == SECTION_INDEX_LOCAL) {
        user = [self.localResults objectAtIndexPath:localIndexPath];
    } else if (indexPath.section == SECTION_INDEX_CLOSE) {
        user = [self.otherCloseResults objectAtIndexPath:localIndexPath];
    } else if (indexPath.section == SECTION_INDEX_FRIENDS) {
        user = [self.friendResults objectAtIndexPath:localIndexPath];
    } else if (indexPath.section == SECTION_INDEX_FRIENDS_ONLINE) {
        user = [self.friendOnlineResults objectAtIndexPath:localIndexPath];
    } else if (indexPath.section == SECTION_INDEX_STRANGERS) {
        user = [self.allResults objectAtIndexPath:localIndexPath];
    } 
    return user;
}

-(UITableViewCell*)tableView:(UITableView *)tableView userCellForUser:(User*)user {
    UserCell *cell = [tableView dequeueReusableCellWithIdentifier:@"UserCell"];
    
    if (!cell) {
        cell = [[UserCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"UserCell"];
    }
    
    [cell setUser:user];

    return cell;
}

-(UITableViewCell*)tableView:(UITableView *)tableView challengeCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    ChallengeCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ChallengeCell"];
    
    if (!cell) {
        cell = [[ChallengeCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ChallengeCell"];
    }
    
    NSIndexPath * localIndexPath = [NSIndexPath indexPathForItem:indexPath.row inSection:0];
    Challenge * challenge = [self.challengeResults objectAtIndexPath:localIndexPath];
    [cell setChallenge:challenge currentUser:self.currentUser];
    
    return cell;    
}

- (NSString*)nameOrYou:(NSString*)name {
    if ([name isEqualToString:self.currentUser.name]) return @"You";
    else return name;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath * localIndexPath = [NSIndexPath indexPathForItem:indexPath.row inSection:0];
    if (indexPath.section == SECTION_INDEX_CHALLENGES)
        [self didSelectChallenge:[self.challengeResults objectAtIndexPath:localIndexPath]];
    else if (indexPath.section == SECTION_INDEX_LOCAL)
        [self didSelectUser:[self.localResults objectAtIndexPath:localIndexPath]];
    else if (indexPath.section == SECTION_INDEX_CLOSE)
        [self didSelectUser:[self.otherCloseResults objectAtIndexPath:localIndexPath]];
    else if (indexPath.section == SECTION_INDEX_FRIENDS)
        [self didSelectUser:[self.friendResults objectAtIndexPath:localIndexPath]];
    else if (indexPath.section == SECTION_INDEX_FRIENDS_ONLINE)
        [self didSelectUser:[self.friendOnlineResults objectAtIndexPath:localIndexPath]];
    else if (indexPath.section == SECTION_INDEX_STRANGERS)
        [self didSelectUser:[self.allResults objectAtIndexPath:localIndexPath]];
    
    else {}
        
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)didSelectUser:(User*)user {
    
    Challenge * existingChallenge = [ChallengeService.shared user:self.currentUser challengedByOpponent:user];
    if (existingChallenge) {
        // accept their challenge instead         
        [ChallengeService.shared acceptChallenge:existingChallenge];
    }
    
    else {
        // Issue the challenge              
        [ChallengeService.shared user:self.currentUser challengeOpponent:user isRemote:!user.isOnline];
        
        // Do NOT join yet (wait until accepted)
    }
}

- (void)didSelectChallenge:(Challenge*)challenge {
    
    // If I have been challenged
    if ([challenge.opponent.userId isEqualToString:self.currentUser.userId]) {
        [ChallengeService.shared acceptChallenge:challenge];
    }
}

- (void)joinMatch:(Challenge*)challenge {
    
    // the challenge is updated, and bindings are fired, BEFORE I get to the end of this block
    // Therefore: make EXTRA SURE you can't join a match while it's going, or you end up joining the same one twice
    
    if (self.currentMatch) return;
    NSLog(@"---- JOIN MATCH (%@) ----", challenge.matchId);
    self.currentChallenge = challenge;
    self.currentMatch = [[MatchViewController alloc] init];
    self.currentMatch.delegate = self;
    [self.currentMatch createMatchWithChallenge:challenge currentWizard:UserService.shared.currentWizard];
    [self.navigationController presentViewController:self.currentMatch animated:YES completion:nil];
    
    // Should be called after viewDidLoad
    [self.currentMatch startMatch];

    // Only the active user broadcasts what he is doing
    [LobbyService.shared user:self.currentUser joinedMatch:challenge.matchId];
}

- (void)didFinishChallenge:(Challenge *)challenge didWin:(BOOL)didWin {
    [UserFriendService.shared user:self.currentUser addChallenge:challenge didWin:didWin];
}

- (void)dealloc {
    // don't worry about disconnecting. If you aren't THERE, it's ok
    NSLog(@"MatchmakingViewController: dealloc");
}


# pragma mark - Buttons n stuff
- (IBAction)didTapInviteFriends:(id)sender {
    
    [AnalyticsService event:@"FriendInviteTap"];          
    
    // Connect their facebook account first, then open the friend invite dialog
    // it doesn't make sense to invite friends without having them connect facebook first
    
    User * user = [UserService.shared currentUser];
    [self showLoading];
    [UserFriendService.shared user:user authenticateFacebook:^(BOOL success, User * updated) {
        [self hideLoading];
        if (updated) {
            [UserService.shared saveCurrentUser];
        }
        
        if (success) {
            [self openFriendPickerThenInviteSingleFriend];
        }
    }];
}

- (void)openFriendPickerThenInviteSingleFriend {
    FBFriendPickerViewController * friends = [[FBFriendPickerViewController alloc] init];
    friends.title = @"Choose a Friend";
    friends.delegate = self;
    friends.allowsMultipleSelection = NO;
    friends.doneButton = nil;
    
    [friends loadData];
    [friends clearSelection];
    
    [self.navigationController presentViewController:friends animated:YES completion:nil];
}

- (void)friendPickerViewControllerSelectionDidChange:(FBFriendPickerViewController *)friendPicker {
    [self facebookViewControllerDoneWasPressed:friendPicker];
}

- (void)facebookViewControllerDoneWasPressed:(id)sender {
    [AnalyticsService event:@"FriendSelected"];
    
    FBFriendPickerViewController *friendPickerController = (FBFriendPickerViewController*)sender;
    NSLog(@"Selected friends: %@", friendPickerController.selection);
    // Dismiss the friend picker
//    [[sender presentingViewController] dismissModalViewControllerAnimated:YES];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    
    NSArray * friendIds = [friendPickerController.selection map:^(NSDictionary*info) {
        return info[@"id"];
    }];
    
    [UserFriendService.shared openFeedDialogTo:friendIds];
}

- (void)facebookViewControllerCancelWasPressed:(id)sender {
    NSLog(@"Canceled");
    // Dismiss the friend picker
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)didTapAccount {
    [AnalyticsService event:@"AccountTap"];    
    SettingsViewController * settings = [SettingsViewController new];
    UINavigationController * navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    settings.onDone = ^{
    };
    [self.navigationController presentViewController:navigation animated:YES completion:nil];
}

@end
