.pragma library

// Pure helpers for PowerBackend. Profiles are stored by their
// power-profiles-daemon names.

function profileName(profile, powerSaver, performance) {
    if (profile === powerSaver)
        return "power-saver";
    if (profile === performance)
        return "performance";
    return "balanced";
}

function profileChoices(options, hasPerformance) {
    return (options || []).filter(function (o) {
        return hasPerformance || o.value !== "performance";
    }).map(function (o) {
        return { value: o.value, label: o.label, icon: o.icon || "", translate: true };
    });
}
