#include "InspCWrapper.m"

// TODO(DavidGoldman): Come up with a better example. This one's log is wayyyy toooo biggg.
%ctor {
  // SBAppSwitcherController.
  /*
  -(void)_rebuildAppListCache;
  -(void)_destroyAppListCache;
  -(void)_cacheAppList;
  -(void)_accessAppListState:(id)state;
  */
  // watchClass(%c(SBAppSwitcherController));
  // watchObject(...);
  watchSelector(@selector(_rebuildAppListCache));
  watchSelector(@selector(_destroyAppListCache));
  watchSelector(@selector(_cacheAppList));
  watchSelector(@selector(_accessAppListState:));

  // SpringBoard application.
  watchSelector(@selector(applicationDidFinishLaunching:));
}
