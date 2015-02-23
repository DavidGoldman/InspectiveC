#include "InspCWrapper.m"

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
  setMaximumRelativeLoggingDepth(4);

  watchSelector(@selector(_rebuildAppListCache));
  watchSelector(@selector(_destroyAppListCache));
  watchSelector(@selector(_cacheAppList));
  watchSelector(@selector(_accessAppListState:));

  // SpringBoard application.
  watchSelector(@selector(applicationDidFinishLaunching:));
}
