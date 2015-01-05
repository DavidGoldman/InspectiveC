/*
  If you link directly with libinspectivec, it will automatically load the dylib into any process
  that you hook into (which is bad if you only want to hook into a single process). You can try
  using this method instead.
 */
#include <dlfcn.h>

typedef void (*inspectiveC_ObjectFuncT)(id obj);
typedef void (*inspectiveC_ClassFuncT)(Class clazz);
typedef void (*inspectiveC_SelFuncT)(SEL _cmd);
typedef void (*inspectiveC_voidFuncT)(void);

static BOOL inspectiveC_hasTriedToLoad = NO;
static void *inspectiveC_Handle = NULL;

static inspectiveC_ObjectFuncT $watchObject;
static inspectiveC_ObjectFuncT $unwatchObject;

static inspectiveC_ClassFuncT $watchClass;
static inspectiveC_ClassFuncT $unwatchClass;

static inspectiveC_SelFuncT $watchSelector;
static inspectiveC_SelFuncT $unwatchSelector;

static inspectiveC_voidFuncT $enableLogging;
static inspectiveC_voidFuncT $disableLogging;

static void * inspectiveC_loadFunctionNamed(const char *name) {
  void *func = dlsym(inspectiveC_Handle, name);
  if (!func) {
    NSLog(@"[InspectiveC Wrapper] Unable to load function %s! Error: %s", name, dlerror());
  }
  return func;
}

static void inspectiveC_init() {
  if (!inspectiveC_hasTriedToLoad) {
    inspectiveC_Handle = dlopen("/usr/lib/libinspectivec.dylib", RTLD_NOW);

    if (inspectiveC_Handle) {
      $watchObject = (inspectiveC_ObjectFuncT)inspectiveC_loadFunctionNamed("InspectiveC_watchObject");
      $unwatchObject = (inspectiveC_ObjectFuncT)inspectiveC_loadFunctionNamed("InspectiveC_unwatchObject");

      $watchClass = (inspectiveC_ClassFuncT)inspectiveC_loadFunctionNamed("InspectiveC_watchInstancesOfClass");
      $unwatchClass = (inspectiveC_ClassFuncT)inspectiveC_loadFunctionNamed("InspectiveC_unwatchInstancesOfClass");

      $watchSelector = (inspectiveC_SelFuncT)inspectiveC_loadFunctionNamed("InspectiveC_watchSelector");
      $unwatchSelector = (inspectiveC_SelFuncT)inspectiveC_loadFunctionNamed("InspectiveC_unwatchSelector");

      $enableLogging = (inspectiveC_voidFuncT)inspectiveC_loadFunctionNamed("InspectiveC_enableLogging");
      $disableLogging = (inspectiveC_voidFuncT)inspectiveC_loadFunctionNamed("InspectiveC_disableLogging");
    } else {
      NSLog(@"[InspectiveC Wrapper] Unable to load libinspectivec! Error: %s", dlerror());
    }

    inspectiveC_hasTriedToLoad = YES;
  }
}

static void watchObject(id obj) {
  inspectiveC_init();
  if ($watchObject) {
    $watchObject(obj);
  }
}
static void unwatchObject(id obj) {
  inspectiveC_init();
  if ($unwatchObject) {
    $unwatchObject(obj);
  }
}

static void watchClass(Class clazz) {
  inspectiveC_init();
  if ($watchClass) {
    $watchClass(clazz);
  }
}
static void unwatchClass(Class clazz) {
  inspectiveC_init();
  if ($unwatchClass) {
    $unwatchClass(clazz);
  }
}

static void watchSelector(SEL _cmd) {
  inspectiveC_init();
  if ($watchSelector) {
    $watchSelector(_cmd);
  }
}
static void unwatchSelector(SEL _cmd) {
  inspectiveC_init();
  if ($unwatchSelector) {
    $unwatchSelector(_cmd);
  }
}

static void enableLogging() {
  inspectiveC_init();
  if ($enableLogging) {
    $enableLogging();
  }
}
static void disableLogging() {
  inspectiveC_init();
  if ($disableLogging) {
    $disableLogging();
  }
}