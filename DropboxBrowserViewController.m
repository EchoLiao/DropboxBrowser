//
//  DropboxBrowserViewController.m
//
//  Created by Daniel Bierwirth on 3/5/12. Edited and Updated by iRare Media on 08/05/14
//  Copyright (c) 2014 iRare Media. All rights reserved.
//
// This code is distributed under the terms and conditions of the MIT license.
//
// Copyright (c) 2014 Daniel Bierwirth and iRare Media
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//

#import <SGNavigationProgress/UINavigationController+SGProgress.h>
#import <UIAlertView+Blocks/UIAlertView+Blocks.h>
#import "DropboxBrowserViewController.h"

// Check for ARC
#if !__has_feature(objc_arc)
    // Add the -fobjc-arc flag to enable ARC for only these files, as described in the ARC documentation: http://clang.llvm.org/docs/AutomaticReferenceCounting.html
    #error DropboxBrowser is built with Objective-C ARC. You must enable ARC for DropboxBrowser.
#endif

static NSString *kNotificationUpdateRootContent = @"NotificationUpdateRootContent";

// View tags to differeniate alert views
static NSUInteger const kDBSignInAlertViewTag = 1;
static NSUInteger const kFileExistsAlertViewTag = 2;
static NSUInteger const kDBSignOutAlertViewTag = 3;

@interface DropboxBrowserViewController () <DBRestClientDelegate>

@property (nonatomic, strong, readwrite) NSString *currentFileName;
@property (nonatomic, strong, readwrite) NSString *currentPath;

@property (nonatomic, strong) DBRestClient *restClient;
@property (nonatomic, strong) DBMetadata *selectedFile;

@property (nonatomic, assign) BOOL isLocalFileOverwritten;
@property (nonatomic, assign) BOOL isSearching;

@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundProcess;

@property (nonatomic, strong) DropboxBrowserViewController *subdirectoryController;

- (DBRestClient *)restClient;

- (void)updateTableData;

- (void)downloadedFile;
- (void)startDownloadFile;
- (void)downloadedFileFailed;
- (void)updateDownloadProgressTo:(CGFloat)progress;

- (BOOL)listDirectoryAtPath:(NSString *)path;

@end

@implementation DropboxBrowserViewController

+ (void)setupDropboxWithAppKey:(NSString *)key appSecret:(NSString *)secret root:(NSString *)root
{
    DBSession *session = [[DBSession alloc] initWithAppKey:key appSecret:secret root:root];
    session.delegate = self;
    [DBSession setSharedSession:session];
}

+ (BOOL)handleOpenURL:(NSURL *)url
{
    if ([[DBSession sharedSession] handleOpenURL:url]) {
        if ([[DBSession sharedSession] isLinked]) {
            NSLog(@"Dropbox app linked successfully!");
            [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationUpdateRootContent object:nil];
        }
        return YES;
    }
    return NO;
}

//------------------------------------------------------------------------------------------------------------//
//------- View Lifecycle -------------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark  - View Lifecycle

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
	self = [super init];
	if (self)  {
        // Custom initialization
        [self basicSetup];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        // Custom Init
        [self basicSetup];
    }
    return self;
}

- (void)basicSetup {
    _currentPath = @"/";
    _isLocalFileOverwritten = NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set Title and Path
    if (self.title == nil || [self.title isEqualToString:@""]) self.title = @"Dropbox";
    if (self.currentPath == nil || [self.currentPath isEqualToString:@""]) self.currentPath = @"/";
    
    // Setup Navigation Bar, use different styles for iOS 7 and higher
    UIBarButtonItem *rightButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Done", @"DropboxBrowser: Done Button to dismiss the DropboxBrowser View Controller") style:UIBarButtonItemStyleDone target:self action:@selector(removeDropboxBrowser)];
    // UIBarButtonItem *leftButton = [[UIBarButtonItem alloc] initWithTitle:@"Logout" style:UIBarButtonItemStylePlain target:self action:@selector(logoutDropbox)];
    self.navigationItem.rightBarButtonItem = rightButton;
    // self.navigationItem.leftBarButtonItem = leftButton;
    
    if (self.shouldDisplaySearchBar == YES) {
        // Create Search Bar
        UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, -44, 320, 44)];
        searchBar.delegate = self;
        searchBar.placeholder = [NSString stringWithFormat:NSLocalizedString(@"Search %@", @"DropboxBrowser: Search Field Placeholder Text. Search 'CURRENT FOLDER NAME'"), self.title];
        self.tableView.tableHeaderView = searchBar;
        
        // Setup Search Controller
//        UISearchDisplayController *searchController = [[UISearchDisplayController alloc] initWithSearchBar:searchBar contentsController:self];
//        searchController.searchResultsDataSource = self;
//        searchController.searchResultsDelegate = self;
//        searchController.delegate = self;
        self.tableView.contentOffset = CGPointMake(0, self.searchDisplayController.searchBar.frame.size.height);
    }

    // Add a refresh control, pull down to refresh
    if ([UIRefreshControl class]) {
        UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
        [refreshControl addTarget:self action:@selector(updateContent) forControlEvents:UIControlEventValueChanged];
        refreshControl.tintColor = [UIRefreshControl appearance].tintColor;
        self.refreshControl = refreshControl;
    }
    
    // Initialize Directory Content
    if ([self.currentPath isEqualToString:@"/"]) {
        [self listDirectoryAtPath:@"/"];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateRootDirectoryContent) name:kNotificationUpdateRootContent object:nil];
    }

    if (self.backgroundColor) {
        self.tableView.backgroundColor = self.backgroundColor;
    }
    if (self.separatorColor) {
        self.tableView.separatorColor = self.separatorColor;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (![self isDropboxLinked]) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Login to Dropbox", @"DropboxBrowser: Alert Title") message:[NSString stringWithFormat:NSLocalizedString(@"%@ is not linked to your Dropbox. Would you like to login now and allow access?", @"DropboxBrowser: Alert Message. 'APP NAME' is not linked to Dropbox..."), [[NSBundle mainBundle] infoDictionary][@"CFBundleDisplayName"]] delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"DropboxBrowser: Alert Button") otherButtonTitles:NSLocalizedString(@"Login", @"DropboxBrowser: Alert Button"), nil];
        alertView.tag = kDBSignInAlertViewTag;
        [alertView show];
    }
}

- (void)logoutOfDropbox {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Logout of Dropbox", @"DropboxBrowser: Alert Title") message:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to logout of Dropbox and revoke Dropbox access for %@?", @"DropboxBrowser: Alert Message. ...revoke Dropbox access for 'APP NAME'"), [[NSBundle mainBundle] infoDictionary][@"CFBundleDisplayName"]] delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"DropboxBrowser: Alert Button") otherButtonTitles:NSLocalizedString(@"Logout", @"DropboxBrowser: Alert Button"), nil];
    alertView.tag = kDBSignOutAlertViewTag;
    [alertView show];
}

//------------------------------------------------------------------------------------------------------------//
//------- Table View -----------------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self.fileList count] == 0) {
        return 2; // Return cell to show the folder is empty
    } else return [self.fileList count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;

    if ([self.fileList count] == 0) {
        // There are no files in the directory - let the user know
        if (indexPath.row == 1) {
            cell = [[UITableViewCell alloc] init];
            if (self.isSearching == YES) {
                cell.textLabel.text = NSLocalizedString(@"No Search Results", @"DropboxBrowser: Empty Search Results Text");
            } else {
                cell.textLabel.text = NSLocalizedString(@"Folder is Empty", @"DropboxBroswer: Empty Folder Text");
            }
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIColor darkGrayColor];
        } else {
            cell = [[UITableViewCell alloc] init];
        }
    } else {
        // Check if the table cell ID has been set, otherwise create one
        if (!self.tableCellID || [self.tableCellID isEqualToString:@""]) {
            self.tableCellID = @"DropboxBrowserCell";
        }
        
        // Create the table view cell
        cell = [tableView dequeueReusableCellWithIdentifier:self.tableCellID];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:self.tableCellID];
        }
        
        // Configure the Dropbox Data for the cell
        DBMetadata *file = (DBMetadata *)(self.fileList)[indexPath.row];
        
        // Setup the cell file name
        cell.textLabel.text = file.filename;
        [cell.textLabel setNeedsDisplay];
        
        // Display icon
        cell.imageView.image = [UIImage imageNamed:file.icon];
        
        // Setup Last Modified Date
        NSLocale *locale = [NSLocale currentLocale];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        NSString *dateFormat = [NSDateFormatter dateFormatFromTemplate:@"E MMM d yyyy" options:0 locale:locale];
        [formatter setDateFormat:dateFormat];
        [formatter setLocale:locale];
        
        // Get File Details and Display
        if ([file isDirectory]) {
            // Folder
            cell.detailTextLabel.text = @"";
            [cell.detailTextLabel setNeedsDisplay];
        } else {
            // File
            cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@, modified %@", @"DropboxBrowser: File detail label with the file size and modified date."), file.humanReadableSize, [formatter stringFromDate:file.lastModifiedDate]];
            [cell.detailTextLabel setNeedsDisplay];
        }
    }
    
    if (self.cellBackgroundColor) {
        cell.backgroundColor = self.cellBackgroundColor;
    }
    if (self.cellSelectedBackgroundView) {
        cell.selectedBackgroundView = self.cellSelectedBackgroundView;
    }
    if (self.cellSelectedBackgroundViewColor) {
        cell.selectedBackgroundView.backgroundColor = self.cellSelectedBackgroundViewColor;
    }
    if (self.textColor) {
        cell.textLabel.textColor = self.textColor;
    }
    if (self.detailTextColor) {
        cell.detailTextLabel.textColor = self.detailTextColor;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath == nil)
        return;
    if ([self.fileList count] == 0) {
        // Do nothing, there are no items in the list. We don't want to download a file that doesn't exist (that'd cause a crash)
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    } else {
        self.selectedFile = (DBMetadata *)(self.fileList)[indexPath.row];
        if ([self.selectedFile isDirectory]) {
            // Create new UITableViewController
            self.subdirectoryController = [[DropboxBrowserViewController alloc] init];
            self.subdirectoryController.backgroundColor = self.backgroundColor;
            self.subdirectoryController.separatorColor = self.separatorColor;
            self.subdirectoryController.cellBackgroundColor = self.cellBackgroundColor;
            self.subdirectoryController.cellSelectedBackgroundView = self.cellSelectedBackgroundView;
            self.subdirectoryController.cellSelectedBackgroundViewColor = self.cellSelectedBackgroundViewColor;
            self.subdirectoryController.textColor = self.textColor;
            self.subdirectoryController.detailTextColor = self.detailTextColor;
            self.subdirectoryController.rootViewDelegate = self.rootViewDelegate;
            NSString *subpath = [self.currentPath stringByAppendingPathComponent:self.selectedFile.filename];
            self.subdirectoryController.currentPath = subpath;
            self.subdirectoryController.title = [subpath lastPathComponent];
            self.subdirectoryController.shouldDisplaySearchBar = self.shouldDisplaySearchBar;
            self.subdirectoryController.deliverDownloadNotifications = self.deliverDownloadNotifications;
            self.subdirectoryController.allowedFileTypes = self.allowedFileTypes;
            self.subdirectoryController.tableCellID = self.tableCellID;
            
            [self.subdirectoryController listDirectoryAtPath:subpath];
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            
            [self.navigationController pushViewController:self.subdirectoryController animated:YES];
        } else {
            self.currentFileName = self.selectedFile.filename;
            
            // Check if our delegate handles file selection
            if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:didSelectFile:)]) {
                [self.rootViewDelegate dropboxBrowser:self didSelectFile:self.selectedFile];
            } else if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:selectedFile:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [self.rootViewDelegate dropboxBrowser:self selectedFile:self.selectedFile];
#pragma clang diagnostic pop
            } else {
                NSString *title = NSLocalizedString(@"Download", nil);
                NSString *cancel = NSLocalizedString(@"Cancel", nil);
                NSString *messag = [NSString stringWithFormat:@"Do you want to download file %@ from Dropbox?", self.selectedFile.filename];
                messag = NSLocalizedString(messag, nil);
                [UIAlertView showWithTitle:title message:messag cancelButtonTitle:cancel otherButtonTitles:@[title] tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                    if (buttonIndex != alertView.cancelButtonIndex) {
                        BOOL rep = [self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:shouldDownloadFile:)];
                        if (!rep || [self.rootViewDelegate dropboxBrowser:self shouldDownloadFile:self.selectedFile]) {
                            [self downloadFile:self.selectedFile replaceLocalVersion:NO];
                        }
                    }
                }];
            }
        }
        
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- SearchBar Delegate ---------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - SearchBar Delegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = NO;
    [searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [[self restClient] searchPath:self.currentPath forKeyword:searchBar.text];
    [searchBar resignFirstResponder];
    
    // We are no longer searching the directory
    self.isSearching = NO;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    // We are no longer searching the directory
    self.isSearching = NO;
    
    // Dismiss the Keyboard
    [searchBar resignFirstResponder];
    
    // Reset the data and reload the table
    [self listDirectoryAtPath:self.currentPath];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    // We are searching the directory
    self.isSearching = YES;
    
    if ([searchBar.text isEqualToString:@""] || searchBar.text == nil) {
        // [searchBar resignFirstResponder];
        [self listDirectoryAtPath:self.currentPath];
    } else if (![searchBar.text isEqualToString:@" "] || ![searchBar.text isEqualToString:@""]) {
        [[self restClient] searchPath:self.currentPath forKeyword:searchBar.text];
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- AlertView Delegate ---------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - AlertView Delegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == kDBSignInAlertViewTag) {
        switch (buttonIndex) {
            case 0:
                [self removeDropboxBrowser];
                break;
            case 1:
                [[DBSession sharedSession] linkFromController:self];
                break;
            default:
                break;
        }
    } else if (alertView.tag == kFileExistsAlertViewTag) {
        switch (buttonIndex) {
            case 0:
                break;
            case 1:
                // User selected overwrite
                [self downloadFile:self.selectedFile replaceLocalVersion:YES];
                break;
            default:
                break;
        }
    } else if (alertView.tag == kDBSignOutAlertViewTag) {
        switch (buttonIndex) {
            case 0: break;
            case 1: {
                [[DBSession sharedSession] unlinkAll];
                [self removeDropboxBrowser];
            } break;
            default:
                break;
        }
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- Content Refresh ------------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Content Refresh

- (void)updateTableData {
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
}

- (void)updateContent {
    [self listDirectoryAtPath:self.currentPath];
}

- (void)updateRootDirectoryContent {
    if ([self.currentPath isEqualToString:@"/"] && ![self.refreshControl isRefreshing]) {
        [self beginRefreshControl:-self.refreshControl.frame.size.height * 2.0];
        if ([self isDropboxLinked]) {
            [[self restClient] loadMetadata:@"/"];
        }
    }
}

//------------------------------------------------------------------------------------------------------------//
//------- DataController Delegate ----------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - DataController Delegate

- (void)removeDropboxBrowser {
    [self dismissViewControllerAnimated:YES completion:^{
        if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowserDismissed:)])
            [[self rootViewDelegate] dropboxBrowserDismissed:self];
    }];
}

- (void)downloadedFile {
    self.tableView.userInteractionEnabled = YES;

    [self.navigationController cancelSGProgress];
    [UIView animateWithDuration:0.75 animations:^{
        self.tableView.alpha = 1.0;
    }];
    
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"File Downloaded", @"DropboxBrowser: Alert Title") message:[NSString stringWithFormat:NSLocalizedString(@"%@ was downloaded from Dropbox.", @"DropboxBrowser: Alert Message"), self.currentFileName] delegate:nil cancelButtonTitle:NSLocalizedString(@"Okay", @"DropboxBrowser: Alert Button") otherButtonTitles:nil];
    [alertView show];
    
    // Deliver File Download Notification
    if (self.deliverDownloadNotifications && [[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        UILocalNotification *localNotification = [[UILocalNotification alloc] init];
        localNotification.alertBody = [NSString stringWithFormat:NSLocalizedString(@"Downloaded %@ from Dropbox", @"DropboxBrowser: Notification Body Text"), self.currentFileName];
        localNotification.soundName = UILocalNotificationDefaultSoundName;
        [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
        if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:deliveredFileDownloadNotification:)])
            [[self rootViewDelegate] dropboxBrowser:self deliveredFileDownloadNotification:localNotification];
    }
    
    if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:didDownloadFile:didOverwriteFile:)]) {
        [self.rootViewDelegate dropboxBrowser:self didDownloadFile:self.currentFileName didOverwriteFile:self.isLocalFileOverwritten];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    } else if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:downloadedFile:isLocalFileOverwritten:)]) {
        [[self rootViewDelegate] dropboxBrowser:self downloadedFile:self.currentFileName isLocalFileOverwritten:self.isLocalFileOverwritten];
    } else if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:downloadedFile:)]) {
        [[self rootViewDelegate] dropboxBrowser:self downloadedFile:self.currentFileName];
    }
#pragma clang diagnostic pop
    
    // End the background task
    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundProcess];
}

- (void)startDownloadFile {
    [self.navigationController setSGProgressPercentage:0 andTintColor:[UIProgressView appearance].tintColor];
}

- (void)downloadedFileFailed {
    self.tableView.userInteractionEnabled = YES;

    [self.navigationController cancelSGProgress];
    [UIView animateWithDuration:0.75 animations:^{
        self.tableView.alpha = 1.0;
    }];
    
    self.navigationItem.title = [self.currentPath lastPathComponent];
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    
    // Deliver File Download Notification
    if (self.deliverDownloadNotifications && [[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        UILocalNotification *localNotification = [[UILocalNotification alloc] init];
        localNotification.alertBody = [NSString stringWithFormat:NSLocalizedString(@"Failed to download %@ from Dropbox.", @"DropboxBrowser: Notification Body Text"), self.currentFileName];
        localNotification.soundName = UILocalNotificationDefaultSoundName;
        [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
        if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:deliveredFileDownloadNotification:)])
            [[self rootViewDelegate] dropboxBrowser:self deliveredFileDownloadNotification:localNotification];
    }
    
    if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:didFailToDownloadFile:)]) {
        [self.rootViewDelegate dropboxBrowser:self didFailToDownloadFile:self.currentFileName];
    } else if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:failedToDownloadFile:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [[self rootViewDelegate] dropboxBrowser:self failedToDownloadFile:self.currentFileName];
#pragma clang diagnostic pop
    }
    
    // End the background task
    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundProcess];
}

- (void)updateDownloadProgressTo:(CGFloat)progress {
    [self.navigationController setSGProgressPercentage:progress * 100 andTintColor:[UIProgressView appearance].tintColor];
}

//------------------------------------------------------------------------------------------------------------//
//------- Files and Directories ------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Dropbox File and Directory Functions

- (void)beginRefreshControl:(NSInteger)yoffset {
    [self.refreshControl endRefreshing];
    [self.tableView setContentOffset:CGPointMake(0, yoffset) animated:YES];
    [self.refreshControl beginRefreshing];
}

- (BOOL)listDirectoryAtPath:(NSString *)path {
    [self beginRefreshControl:-self.refreshControl.frame.size.height];
    if ([self isDropboxLinked]) {
        [[self restClient] loadMetadata:path];
        return YES;
    } else return NO;
}

- (BOOL)isDropboxLinked {
    return [[DBSession sharedSession] isLinked];
}

- (BOOL)downloadFile:(DBMetadata *)file replaceLocalVersion:(BOOL)replaceLocalVersion {
    // Begin Background Process
    self.backgroundProcess = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundProcess];
        self.backgroundProcess = UIBackgroundTaskInvalid;
    }];
    
    // Check if the file is a directory
    if (file.isDirectory) return NO;
    
    // Set download success
    BOOL downloadSuccess = NO;
    
    // Setup the File Manager
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Create the local file path
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *localPath = [documentsPath stringByAppendingPathComponent:file.filename];
    
    // Check if the local version should be overwritten
    if (replaceLocalVersion) {
        self.isLocalFileOverwritten = YES;
        [fileManager removeItemAtPath:localPath error:nil];
    } else self.isLocalFileOverwritten = NO;
    
    // Check if a file with the same name already exists locally
    if ([fileManager fileExistsAtPath:localPath] == NO) {
        // Prevent the user from downloading any more files while this donwload is in progress
        self.tableView.userInteractionEnabled = NO;
        [UIView animateWithDuration:0.75 animations:^{
            self.tableView.alpha = 0.8;
        }];
        
        // Start the file download
        [self startDownloadFile];
        [[self restClient] loadFile:file.path intoPath:localPath];
        
        // The download was a success
        downloadSuccess = YES;
        
    } else {
        // Create the local URL and get the modification date
        NSURL *fileUrl = [NSURL fileURLWithPath:localPath];
        NSDate *fileDate;
        NSError *error;
        [fileUrl getResourceValue:&fileDate forKey:NSURLContentModificationDateKey error:&error];
        
        if (!error) {
            NSComparisonResult result;
            result = [file.lastModifiedDate compare:fileDate]; // Compare the Dates
            
            if (result == NSOrderedAscending) {
                // Dropbox file is older than local file
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"File Conflict", @"DropboxBrowser: Alert Title") message:[NSString stringWithFormat:NSLocalizedString(@"%@ has already been downloaded from Dropbox. You can overwrite the local version with the Dropbox one. The file in local files is newer than the Dropbox file.", @"DropboxBrowser: Alert Message"), file.filename] delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"DropboxBrowser: Alert Button") otherButtonTitles:NSLocalizedString(@"Overwrite", @"DropboxBrowser: Alert Button"), nil];
                alertView.tag = kFileExistsAlertViewTag;
                [alertView show];
                
                NSDictionary *infoDictionary = @{@"file": file, @"message": @"File already exists in Dropbox and locally. The local file is newer."};
                NSError *error = [NSError errorWithDomain:@"[DropboxBrowser] File Conflict Error: File already exists in Dropbox and locally. The local file is newer." code:kDBDropboxFileOlderError userInfo:infoDictionary];
                
                if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:fileConflictWithLocalFile:withDropboxFile:withError:)]) {
                    [self.rootViewDelegate dropboxBrowser:self fileConflictWithLocalFile:fileUrl withDropboxFile:file withError:error];
                } else if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:fileConflictError:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    [[self rootViewDelegate] dropboxBrowser:self fileConflictError:infoDictionary];
#pragma clang diagnostic pop
                }
                
            } else if (result == NSOrderedDescending) {
                // Dropbox file is newer than local file
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"File Conflict", @"DropboxBrowser: Alert Title") message:[NSString stringWithFormat:NSLocalizedString(@"%@ has already been downloaded from Dropbox. You can overwrite the local version with the Dropbox file. The file in Dropbox is newer than the local file.", @"DropboxBrowser: Alert Message"), file.filename] delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"DropboxBrowser: Alert Button") otherButtonTitles:NSLocalizedString(@"Overwrite", @"DropboxBrowser: Alert Button"), nil];
                alertView.tag = kFileExistsAlertViewTag;
                [alertView show];
                
                NSDictionary *infoDictionary = @{@"file": file, @"message": @"File already exists in Dropbox and locally. The Dropbox file is newer."};
                NSError *error = [NSError errorWithDomain:@"[DropboxBrowser] File Conflict Error: File already exists in Dropbox and locally. The Dropbox file is newer." code:kDBDropboxFileNewerError userInfo:infoDictionary];
                
                if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:fileConflictWithLocalFile:withDropboxFile:withError:)]) {
                    [self.rootViewDelegate dropboxBrowser:self fileConflictWithLocalFile:fileUrl withDropboxFile:file withError:error];
                } else if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:fileConflictError:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    [[self rootViewDelegate] dropboxBrowser:self fileConflictError:infoDictionary];
#pragma clang diagnostic pop
                }
            } else if (result == NSOrderedSame) {
                // Dropbox File and local file were both modified at the same time
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"File Conflict", @"DropboxBrowser: Alert Title") message:[NSString stringWithFormat:NSLocalizedString(@"%@ has already been downloaded from Dropbox. You can overwrite the local version with the Dropbox file. Both the local file and the Dropbox file were modified at the same time.", @"DropboxBrowser: Alert Message"), file.filename] delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"DropboxBrowser: Alert Button") otherButtonTitles:NSLocalizedString(@"Overwrite", @"DropboxBrowser: Alert Button"), nil];
                alertView.tag = kFileExistsAlertViewTag;
                [alertView show];
                
                NSDictionary *infoDictionary = @{@"file": file, @"message": @"File already exists in Dropbox and locally. Both files were modified at the same time."};
                NSError *error = [NSError errorWithDomain:@"[DropboxBrowser] File Conflict Error: File already exists in Dropbox and locally. Both files were modified at the same time." code:kDBDropboxFileSameAsLocalFileError userInfo:infoDictionary];
                
                if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:fileConflictWithLocalFile:withDropboxFile:withError:)]) {
                    [self.rootViewDelegate dropboxBrowser:self fileConflictWithLocalFile:fileUrl withDropboxFile:file withError:error];
                } else if ([[self rootViewDelegate] respondsToSelector:@selector(dropboxBrowser:fileConflictError:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    [[self rootViewDelegate] dropboxBrowser:self fileConflictError:infoDictionary];
#pragma clang diagnostic pop
                }
            }
            
            [self updateTableData];
        } else {
            downloadSuccess = NO;
        }
    }
    
    return downloadSuccess;
}

- (void)loadShareLinkForFile:(DBMetadata*)file {
    [self.restClient loadSharableLinkForFile:file.path shortUrl:YES];
}

//------------------------------------------------------------------------------------------------------------//
//------- Dropbox Delegate -----------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - DBRestClientDelegate Methods

- (DBRestClient *)restClient {
    if (!_restClient) {
        _restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        _restClient.delegate = self;
    }
    return _restClient;
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata {
    NSMutableArray *dirList = [[NSMutableArray alloc] init];
    
    if (metadata.isDirectory) {
        for (DBMetadata *file in metadata.contents) {
            if (![file.filename hasSuffix:@".exe"]) {
                // Add to list if not '.exe' and either the file is a directory, there are no allowed files set or the file ext is contained in the allowed types
                if ([file isDirectory] || self.allowedFileTypes.count == 0 || [self.allowedFileTypes containsObject:[file.filename pathExtension].lowercaseString] ) {
                    [dirList addObject:file];
                }
            }
        }
    }
    
    self.fileList = dirList;
    
    [self updateTableData];
}

- (void)restClient:(DBRestClient *)client loadedSearchResults:(NSArray *)results forPath:(NSString *)path keyword:(NSString *)keyword {
    self.fileList = [NSMutableArray arrayWithArray:results];
    [self updateTableData];
}

- (void)restClient:(DBRestClient *)restClient searchFailedWithError:(NSError *)error {
    [self updateTableData];
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error {
    [self updateTableData];
}

- (void)restClient:(DBRestClient *)client loadedFile:(NSString *)localPath {
    [self downloadedFile];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error {
    [self downloadedFileFailed];
}

- (void)restClient:(DBRestClient *)client loadProgress:(CGFloat)progress forFile:(NSString *)destPath {
    [self updateDownloadProgressTo:progress];
}

- (void)restClient:(DBRestClient *)client loadedSharableLink:(NSString *)link forFile:(NSString *)path {
    if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:didLoadShareLink:)]) {
        [self.rootViewDelegate dropboxBrowser:self didLoadShareLink:link];
    }
}

- (void)restClient:(DBRestClient *)client loadSharableLinkFailedWithError:(NSError *)error {
    if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:didFailToLoadShareLinkWithError:)]) {
        [self.rootViewDelegate dropboxBrowser:self didFailToLoadShareLinkWithError:error];
    } else if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:failedLoadingShareLinkWithError:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.rootViewDelegate dropboxBrowser:self failedLoadingShareLinkWithError:error];
#pragma clang diagnostic pop
    }
}

#pragma mark - DBSessionDelegate

+ (void)sessionDidReceiveAuthorizationFailure:(DBSession*)session userId:(NSString *)userId
{
    NSString *title = NSLocalizedString(@"Dropbox Session Ended", nil);
    NSString *messag = NSLocalizedString(@"Do you want to relink?", nil);
    NSString *cancel = NSLocalizedString(@"Cancel", nil);
    NSString *relink = NSLocalizedString(@"Relink", nil);
    [UIAlertView showWithTitle:title message:messag cancelButtonTitle:cancel otherButtonTitles:@[relink] tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex != alertView.cancelButtonIndex) {
            [[DBSession sharedSession] linkUserId:userId fromController:nil];
        }
    }];
}

//------------------------------------------------------------------------------------------------------------//
//------- Deprecated Methods ---------------------------------------------------------------------------------//
//------------------------------------------------------------------------------------------------------------//
#pragma mark - Deprecated Methods

- (NSString *)fileName {
    for (int i = 0; i <= 5; i++)
        NSLog(@"[DropboxBrowser] WARNING: The fileName method is deprecated. Use the currentFileName property instead. This method will become unavailable in a future version.");
    return self.currentFileName;
}

@end
