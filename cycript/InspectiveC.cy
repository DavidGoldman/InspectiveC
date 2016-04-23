var intFunc = @encode(void(int));
var objFunc = @encode(void(id));
var classFunc = @encode(void(Class));
var selFunc = @encode(void(SEL));
var voidFunc = @encode(void());
var objSelFunc = @encode(void(id, SEL));
var classSelFunc = @encode(void(Class, SEL));

var handle = dlopen("/usr/lib/libinspectivec.dylib", RTLD_NOW);

var setMaximumRelativeLoggingDepth = intFunc(dlsym(handle, "InspectiveC_setMaximumRelativeLoggingDepth"));

var watchObject = objFunc(dlsym(handle, "InspectiveC_watchObject"));
var unwatchObject = objFunc(dlsym(handle, "InspectiveC_unwatchObject"));
var watchSelectorOnObject = objSelFunc(dlsym(handle, "InspectiveC_watchSelectorOnObject"));
var unwatchSelectorOnObject = objSelFunc(dlsym(handle, "InspectiveC_unwatchSelectorOnObject"));

var watchClass = classFunc(dlsym(handle, "InspectiveC_watchInstancesOfClass"));
var unwatchClass = classFunc(dlsym(handle, "InspectiveC_unwatchInstancesOfClass"));
var watchSelectorOnClass = classSelFunc(dlsym(handle, "InspectiveC_watchSelectorOnInstancesOfClass"));
var unwatchSelectorOnClass = classSelFunc(dlsym(handle, "InspectiveC_unwatchSelectorOnInstancesOfClass"));

var watchSelector = selFunc(dlsym(handle, "InspectiveC_watchSelector"));
var unwatchSelector = selFunc(dlsym(handle, "InspectiveC_unwatchSelector"));

var enableLogging = voidFunc(dlsym(handle, "InspectiveC_enableLogging"));
var disableLogging = voidFunc(dlsym(handle, "InspectiveC_disableLogging"));

var enableCompleteLogging = voidFunc(dlsym(handle, "InspectiveC_enableCompleteLogging"));
var disableCompleteLogging = voidFunc(dlsym(handle, "InspectiveC_disableCompleteLogging"));

var flushLogFile = voidFunc(dlsym(handle, "InspectiveC_flushLogFile"));
