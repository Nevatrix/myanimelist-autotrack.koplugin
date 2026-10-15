-- tiny translation layer. strings in the code are english,
-- this table maps them to spanish. anything missing just stays in english

local I18n = { lang = "en" }

local es = {
    ["Couldn't check for updates: %1"] = "No pude revisar actualizaciones: %1",
    ["You're on the latest version (%1)."] = "Ya tienes la última versión (%1).",
    ["There's a new version of MyAnimeList Autotrack: %1 (you have %2).\n\nUpdate now?"] = "Hay una versión nueva de MyAnimeList Autotrack: %1 (tienes %2).\n\n¿Actualizar ahora?",
    ["Update"] = "Actualizar",
    ["MyAnimeList Autotrack was updated to %1. Restart KOReader to use it."] = "MyAnimeList Autotrack se actualizó a %1. Reinicia KOReader para usarla.",
    ["Update failed: %1"] = "Falló la actualización: %1",
    ["ch. %1"] = "cap. %1",
    ["MAL: couldn't find \"%1\". Use the menu to search for it by hand."] = "MAL: no encontré «%1». Usa el menú para buscarlo a mano.",
    [" · %1 vols."] = " · %1 vol.",
    ["Search again…"] = "Buscar otro…",
    ["Ignore series"] = "Ignorar serie",
    ["Not now"] = "Ahora no",
    ["MAL: which one is \"%1\"?"] = "MAL: ¿cuál es «%1»?",
    ["Search MyAnimeList (or type the ID)"] = "Buscar en MyAnimeList (o escribe el ID)",
    ["Cancel"] = "Cancelar",
    ["Search"] = "Buscar",
    ["You need an internet connection."] = "Necesitas conexión a internet.",
    ["Linked to: %1"] = "Asignado: %1",
    ["Couldn't find that ID."] = "No encontré ese ID.",
    ["No results."] = "Sin resultados.",
    ["Enabled"] = "Activado",
    ["Confirm new series before linking them"] = "Confirmar series nuevas antes de asignarlas",
    ["Current book: not recognized"] = "Libro actual: no reconocido",
    [" · ch. %1"] = " · cap. %1",
    ["Detected: %1%2%3"] = "Detectado: %1%2%3",
    ["MAL series: not linked"] = "Serie en MAL: sin asignar",
    ["MAL series: ignored"] = "Serie en MAL: ignorada",
    ["MAL series: %1 (#%2)"] = "Serie en MAL: %1 (#%2)",
    ["Change / search series on MAL…"] = "Cambiar / buscar serie en MAL…",
    ["Ignore this series"] = "Ignorar esta serie",
    ["This series won't be synced."] = "Esta serie no se sincronizará.",
    ["Forget the link for this series"] = "Olvidar asignación de esta serie",
    ["Done. It'll be searched again next time."] = "Listo. Se volverá a buscar la próxima vez.",
    ["Sync now"] = "Sincronizar ahora",
    ["Queued updates: %1"] = "Pendientes en cola: %1",
    ["Nothing queued."] = "No hay nada pendiente.",
    ["Clear queue"] = "Vaciar cola",
    ["Check for updates automatically (once a day)"] = "Buscar actualizaciones solo (1 vez al día)",
    ["Check for updates now (you have %1)"] = "Buscar actualizaciones ahora (tienes %1)",
    ["Test MAL connection"] = "Probar conexión con MAL",
    ["The .env file is missing from the plugin folder."] = "Falta el archivo .env en la carpeta del plugin.",
    ["Connected as %1"] = "Conectado como %1",
    ["Language"] = "Idioma",
    ["Automatic (KOReader: %1)"] = "Automático (KOReader: %1)",
    ["Use Wikipedia for volume/chapter info"] = "Usar Wikipedia para datos de tomos/capítulos",
    ["Wikipedia: not checked yet"] = "Wikipedia: aún no consultada",
    ["Wikipedia: no chapter list found"] = "Wikipedia: no encontré lista de capítulos",
    ["Wikipedia: %1 (%2 vols)"] = "Wikipedia: %1 (%2 tomos)",
}

local tables = { es = es }

I18n.languages = {
    { code = "en", name = "English" },
    { code = "es", name = "Español" },
}

-- koreader's own ui language, e.g. "es", "en", "pt_BR"
function I18n.koreaderLang()
    local lang = G_reader_settings and G_reader_settings:readSetting("language") or "en"
    return (tostring(lang):match("^(%a%a)") or "en"):lower()
end

-- "auto" follows koreader
function I18n.set(choice)
    local lang = (choice == nil or choice == "auto") and I18n.koreaderLang() or choice
    I18n.lang = tables[lang] and lang or "en"
end

function I18n.t(s)
    local tbl = tables[I18n.lang]
    return tbl and tbl[s] or s
end

return I18n
