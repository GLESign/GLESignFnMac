#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PopupTab) {
    PopupTabSensitivity = 0,
    PopupTabKeyRemap    = 1,
    PopupTabController  = 2,
    PopupTabContainer   = 3,
    PopupTabQuickStart  = 4,
};

@interface popupViewController : UIViewController <UITextFieldDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UIView *sensitivityTab;
@property (nonatomic, strong) UIView *keyRemapTab;
@property (nonatomic, strong) UIView *containerTab;
@property (nonatomic, strong) UIView *quickStartTab;
@property (nonatomic, strong) UIView *controllerTab;

@property (nonatomic, strong) UIButton *sensitivityTabButton;
@property (nonatomic, strong) UIButton *keyRemapTabButton;
@property (nonatomic, strong) UIButton *containerTabButton;
@property (nonatomic, strong) UIButton *quickStartTabButton;
@property (nonatomic, strong) UIButton *controllerTabButton;

@property (nonatomic, strong) UIView *tabIndicator;

@property (nonatomic, strong) UIView *segmentedContainer;

@property (nonatomic, assign) PopupTab currentTab;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *stagedKeybinds;

@property (nonatomic, strong) UIButton *applyChangesButton;
@property (nonatomic, strong) UIButton *discardKeybindsButton;
@property (nonatomic, strong) UIButton *applyControllerButton;
@property (nonatomic, strong) UIButton *discardControllerButton;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *stagedControllerMappings;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *stagedVCtrlRemappings;

@property (nonatomic, strong) UIButton *discardSensitivityButton;
@property (nonatomic, strong) UIButton *applySensitivityButton;

- (void)switchToQuickStartTab;

- (void)switchToControllerTab;

@end
