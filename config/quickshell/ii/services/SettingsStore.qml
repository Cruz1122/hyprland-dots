pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root

    signal operationStarted(string key, var requestedValue)
    signal operationSucceeded(string key, var requestedValue, var effectiveValue)
    signal operationFailed(string key, var requestedValue, string message)

    property string lastOperationKey: ""
    property string lastStatus: "idle"
    property string lastMessage: ""

    function value(key) {
        const parts = key.split(".");
        let current = Config.options;
        for (let i = 0; i < parts.length; i++) {
            if (current === undefined || current === null) return undefined;
            current = current[parts[i]];
        }
        return current;
    }

    function validate(setting, requestedValue) {
        if (!setting) return "Unknown setting";
        if (setting.type === "boolean" && typeof requestedValue !== "boolean") return "Expected a boolean value";
        if (setting.type === "number") {
            if (typeof requestedValue !== "number" || Number.isNaN(requestedValue)) return "Expected a number";
            if (setting.min !== undefined && requestedValue < setting.min) return `Value must be >= ${setting.min}`;
            if (setting.max !== undefined && requestedValue > setting.max) return `Value must be <= ${setting.max}`;
        }
        if (setting.type === "path" && typeof requestedValue !== "string") return "Expected a path string";
        if (setting.type === "enum") {
            if (typeof requestedValue !== "string") return "Expected a string value";
            if (!setting.options || setting.options.indexOf(requestedValue) < 0) return "Value is not allowed";
        }
        return "";
    }

    function setValue(key, requestedValue) {
        const setting = SettingsRegistry.settingByKey(key);
        const validationError = root.validate(setting, requestedValue);
        root.lastOperationKey = key;
        root.lastStatus = "pending";
        root.lastMessage = "Applying";
        root.operationStarted(key, requestedValue);

        if (validationError.length > 0) {
            root.lastStatus = "error";
            root.lastMessage = validationError;
            root.operationFailed(key, requestedValue, validationError);
            return false;
        }

        try {
            Config.setNestedValue(key, requestedValue);
            const effectiveValue = root.value(key);
            root.lastStatus = "success";
            root.lastMessage = "Applied";
            root.operationSucceeded(key, requestedValue, effectiveValue);
            return true;
        } catch (error) {
            const message = String(error);
            root.lastStatus = "error";
            root.lastMessage = message;
            root.operationFailed(key, requestedValue, message);
            return false;
        }
    }
}
