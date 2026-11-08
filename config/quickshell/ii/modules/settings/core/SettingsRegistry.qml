pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "SettingsLogic.js" as Logic

// Settings metadata from modules/settings/registry/*.json, read synchronously
// at startup so pages and search never see a half-loaded registry. A broken
// page file is reported in loadErrors and rendered as an empty page.
Singleton {
    id: root

    readonly property string registryDir: Quickshell.shellPath("modules/settings/registry")
    property bool ready: false
    property var loadErrors: []
    property var groups: []
    property var pages: []
    property var footerPages: []
    property var retired: ({ retired: [], managedElsewhere: [] })
    property var model: null
    property var _synthetic: ({})
    // Search documents cache. Mutated in place (never reassigned) so that
    // search() can run inside bindings without notifying them.
    readonly property var _searchCache: ({ docs: null, language: "" })

    function page(id) {
        return root.model?.pageById[id] ?? null;
    }

    // Canonical entry for a key. Keys written by a custom entry (its `keys`)
    // resolve to a minimal entry owned by that custom entry.
    function entry(key) {
        if (!root.model)
            return null;
        const found = root.model.entryByKey[key];
        if (found)
            return found;
        const owner = root.model.ownerByKey[key];
        if (!owner)
            return null;
        if (!root._synthetic[key]) {
            root._synthetic[key] = {
                key: key, path: key, backend: owner.backend, type: "custom", widget: "custom",
                label: owner.label, description: "", note: "", keywords: [], icon: "",
                section: owner.section, pageId: owner.pageId, homePageId: owner.pageId, aliasOf: "",
                risky: owner.risky, owner: owner.key
            };
        }
        return root._synthetic[key];
    }

    function allEntries() {
        return root.model ? Object.values(root.model.entryByKey) : [];
    }

    function homePageId(key) {
        return root.entry(key)?.pageId ?? "";
    }

    // Entries shown on a page, aliases included (resolved to their canonical entry).
    function entriesForPage(id) {
        return root.page(id)?.entries ?? [];
    }

    function sections(pageId) {
        return root.page(pageId)?.sections ?? [];
    }

    function section(pageId, sectionId) {
        return root.sections(pageId).find(s => s.id === sectionId) ?? null;
    }

    function entriesForSection(pageId, sectionId) {
        return root.entriesForPage(pageId).filter(e => e.section === sectionId);
    }

    function isRetired(path) {
        return Logic.isRetired(path, root.retired);
    }

    // Ranked results: { kind, pageId, sectionId, key, score }. Aliases never
    // appear; results point at the canonical page and section.
    function search(query, limit) {
        if (!root.model)
            return [];
        const language = `${Translation.languageCode}:${Translation.isLoading}:${Object.keys(Translation.translations).length}`;
        const cache = root._searchCache;
        if (!cache.docs || cache.language !== language) {
            cache.docs = Logic.searchDocuments(root.model, text => Translation.tr(text));
            cache.language = language;
        }
        return Logic.search(cache.docs, query, limit ?? 20);
    }

    // One FileView per file: reusing a FileView with a new path can return
    // the previous file's text.
    function _readJson(name, errors) {
        const reader = readerComponent.createObject(root, { path: `${root.registryDir}/${name}` });
        const text = reader.text();
        reader.destroy();
        if (!text || text.length === 0) {
            errors.push(`registry/${name}: missing or empty`);
            return null;
        }
        try {
            return JSON.parse(text);
        } catch (e) {
            errors.push(`registry/${name}: ${e.message}`);
            return null;
        }
    }

    function _load() {
        const errors = [];
        const pagesDoc = root._readJson("pages.json", errors);
        const retiredDoc = root._readJson("retired.json", errors) ?? { retired: [], managedElsewhere: [] };
        const ids = [];
        for (const group of (pagesDoc?.groups ?? []))
            ids.push(...(group.pages ?? []));
        ids.push(...(pagesDoc?.footer ?? []));
        const docs = {};
        for (const id of ids)
            docs[id] = root._readJson(`${id}.json`, errors);
        const built = Logic.buildRegistry(pagesDoc, docs, retiredDoc);
        root.retired = built.retired;
        root.model = built;
        root.groups = built.groups;
        root.footerPages = built.footerPages;
        root.pages = built.pages;
        root.loadErrors = errors.concat(built.errors);
        for (const error of root.loadErrors)
            console.warn(`[SettingsRegistry] ${error}`);
        root.ready = true;
    }

    Component {
        id: readerComponent
        FileView {
            blockLoading: true
            printErrors: false
        }
    }

    Component.onCompleted: root._load()
}
