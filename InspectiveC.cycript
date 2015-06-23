intFunc = @encode(void(int));
objFunc = @encode(void(id));
classFunc = @encode(void(Class));
selFunc = @encode(void(SEL));
voidFunc = @encode(void(void));
objSelFunc = @encode(void(id, SEL));
classSelFunc = @encode(void(Class, SEL));

handle = dlopen("/usr/lib/libinspectivec.dylib", RTLD_NOW);

setMaximumRelativeLoggingDepth = intFunc(dlsym(handle, "InspectiveC_setMaximumRelativeLoggingDepth"));

watchObject = objFunc(dlsym(handle, "InspectiveC_watchObject"));
unwatchObject = objFunc(dlsym(handle, "InspectiveC_unwatchObject"));
watchSelectorOnObject = objSelFunc(dlsym(handle, "InspectiveC_watchSelectorOnObject"));
unwatchSelectorOnObject = objSelFunc(dlsym(handle, "InspectiveC_unwatchSelectorOnObject"));

watchClass = classFunc(dlsym(handle, "InspectiveC_watchInstancesOfClass"));
unwatchClass = classFunc(dlsym(handle, "InspectiveC_unwatchInstancesOfClass"));
watchSelectorOnClass = classSelFunc(dlsym(handle, "InspectiveC_watchSelectorOnInstancesOfClass"));
unwatchSelectorOnClass = classSelFunc(dlsym(handle, "InspectiveC_unwatchSelectorOnInstancesOfClass"));

watchSelector = selFunc(dlsym(handle, "InspectiveC_watchSelector"));
unwatchSelector = selFunc(dlsym(handle, "InspectiveC_unwatchSelector"));

enableLogging = voidFunc(dlsym(handle, "InspectiveC_enableLogging"));
disableLogging = voidFunc(dlsym(handle, "InspectiveC_disableLogging"));

enableCompleteLogging = voidFunc(dlsym(handle, "InspectiveC_enableCompleteLogging"));
disableCompleteLogging = voidFunc(dlsym(handle, "InspectiveC_disableCompleteLogging"));
