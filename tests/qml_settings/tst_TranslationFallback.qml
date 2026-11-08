import QtQuick
import QtTest
import "../../config/quickshell/ii/services/TranslationFallback.js" as Fallback

TestCase {
    name: "TranslationFallback"

    function test_normalize() {
        compare(Fallback.normalize("es_CO.UTF-8"), "es_CO");
        compare(Fallback.normalize("es-co"), "es_CO");
        compare(Fallback.normalize("de_DE@euro"), "de_DE");
        compare(Fallback.normalize("fr"), "fr");
    }

    function test_exact_then_same_language_then_english() {
        compare(Fallback.candidates("es_CO.UTF-8", ["en_US", "es_MX", "es_AR"]), ["es_CO", "es_MX", "es_ES", "es_AR"]);
        compare(Fallback.candidates("es_MX", ["es_MX"]), ["es_MX", "es_ES"]);
        compare(Fallback.candidates("de_AT", ["de_DE"]), ["de_AT", "de_DE"]);
        compare(Fallback.candidates("C", []), []);
        compare(Fallback.candidates("", []), []);
    }

    function test_non_object_translation_is_empty() {
        compare(Fallback.sanitize(null), {});
        compare(Fallback.sanitize([1]), {});
        compare(Fallback.sanitize(3), {});
        compare(Fallback.sanitize({ a: "b" }), { a: "b" });
    }
}
