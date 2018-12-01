local LrDialogs = import 'LrDialogs'
local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrFunctionContext = import 'LrFunctionContext'
local LrFileUtils = import 'LrFileUtils'

-- cache for temporary developer presets
local developPresetCache = {}

-- this table represents a map from the terms used in the EXIF data to the ones used in Lightroom
local cameraProfilePresets = { 
    ["F2/Fujichrome (Velvia)"] = "Camera Velvia/Vivid",
    ["F1b/Studio Portrait Smooth Skin Tone (Astia)"] = "Camera ASTIA/Soft",
    ["F0/Standard (Provia)"] = "Camera PROVIA/Standard",
    ["Classic Chrome"] = "Camera CLASSIC CHROME",
    ["Pro Neg. Hi"] = "Camera Pro Neg Hi",
    ["Pro Neg. Std"] = "Camera Pro Neg Std",
    ["Acros"] = "Camera ACROS",
    ["Acros Yellow Filter"] = "Camera ACROS+Ye Filter",
    ["Acros Red Filter"] = "Camera ACROS+R Filter",
    ["Acros Green Filter"] = "Camera ACROS+G Filter",
    ["None (B&W)"] = "Camera Monochrome",
    ["B&W Yellow Filter"] = "Camera Monochrome+Ye Filter",
    ["B&W Red Filter"] = "Camera Monochrome+R Filter",
    ["B&W Green Filter"] = "Camera Monochrome+G Filter",
    -- Sepia not yet supported by Lightroom
    ["B&W Sepia"] = "Camera Monochrome", 
}

-- retrieve all selected photos
-- catalog: LrCatalog
-- returns an array of LrPhoto or nil
local function getSelectedPhotos ( catalog )
    if catalog:getTargetPhoto () then
        return catalog:getTargetPhotos()
    else
        return nil
    end
end

-- construct a string that consists of the paths for each photo, separated by spaces
-- photos: array of LrPhoto
-- returns a string
local function getPhotoPaths ( photos )
    local photoPaths = ""
    for _, photo in ipairs(photos) do
        -- have to surround the path in quotation marks in case the path has spaces
        local photoPath = string.format("\'%s\'", photo:getRawMetadata("path"))
        photoPaths = photoPaths .. photoPath .. " "
    end
    return photoPaths
end

-- helper function for getFilmSims
-- s: string
-- returns an array of strings
-- NOTE: For some reason, Fujifilm cameras put their film profile data in one of two fields: Film Mode or Saturation.
--       For color photos, the data ends up in FilmMode, whereas b&w photos' film simulation keys end up in Saturation.
--       Thus, in the call to exiftools (see below), I request the data for both fields. If FilmMode is null, 
--       the value is "-". For Saturation, it's "0 (normal)". 
local function resultStringToFilmSims( s )
    local sims = {}
    for line in string.gmatch(s, "[^\r\n]+") do
        -- the returned FilmMode and Saturation fields are separated by tabs
        for entry in string.gmatch(line, "[^\t]+") do
            if entry ~= "-" and entry ~= "0 (normal)" then
                table.insert(sims, entry)
                break
            end
        end
    end
    return sims;
end

-- given an array of photos, return an array of the film profile keys from the camera EXIF data
-- photos: array of LrPhoto
-- returns an array of strings
-- NOTE: see above resultStringToFilmSims documentation for explanation of the exiftool command
local function getFilmSims( photos )
    local photoPaths = getPhotoPaths(photos)
    local dummyFile = _PLUGIN.path .. "/filmmode.txt"
    LrTasks.execute(_PLUGIN.path .. "/exiftool -T -FilmMode -Saturation " .. photoPaths .. "> " .. dummyFile)
    local resultString = LrFileUtils.readFile(dummyFile)
    LrFileUtils.delete(dummyFile)
    return resultStringToFilmSims(resultString)
end

-- once we have all the selected photos and their corresponding film simulation EXIF data, all that's left is to apply them in LR
-- photos: array of LrPhoto
-- filmSims: array of strings
local function applyFilmSims( photos, filmSims )
    for i, photo in ipairs(photos) do
        local sim = filmSims[i]
        -- retrieve the corresponding keys for CameraProfile in LightRoom
        local lightroomSimName = cameraProfilePresets[sim]
        local cachedPreset = developPresetCache[lightroomSimName]
        if (cachedPreset) then
            photo:applyDevelopPreset(cachedPreset, _PLUGIN)
        else
            newPreset = LrApplication.addDevelopPresetForPlugin(_PLUGIN, lightroomSimName, {["CameraProfile"]=lightroomSimName})
            developPresetCache[lightroomSimName] = newPreset
            photo:applyDevelopPreset(newPreset, _PLUGIN)
        end
    end
end


LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local selectedPhotos = getSelectedPhotos(catalog)
    -- there should always be selected photos because otherwise the menu item won't be selectable
    if (selectedPhotos) then 
        filmSims = getFilmSims(selectedPhotos)
        catalog:withWriteAccessDo("update film simulations for selected photos", function(context)
            applyFilmSims(selectedPhotos, filmSims)
        end )
    end  
end )
