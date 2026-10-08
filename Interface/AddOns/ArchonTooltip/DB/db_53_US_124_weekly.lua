local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Warrior-Arms','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','DemonHunter-Vengeance','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Shaman-Elemental','Druid-Restoration','Unknown-Unknown','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Priest-Discipline','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Enhancement','Evoker-Devastation','Druid-Balance','Monk-Windwalker','Warrior-Protection','Monk-Mistweaver','Monk-Brewmaster','Paladin-Holy','Priest-Shadow',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aakier:BAABNQAECoFAAAIBAAkKHB4TJQAVAwABAAkKHB4TJQAVAwAAAA==.',
Ac='Acanda:BAAANQAFFAIIAgAAAA==.',
Ad='Aderai:BAAANQADCggICAAAAA==.Adolina:BAABNQAECoEvAAICAAkKfRxjJwCmAgACAAkKfRxjJwCmAgAAAA==.',
Ak='Akier:BAAANQAECgMIAwABNQAECgkJQAABABweAA==.',
Ap='Applebutter:BAAANQAECgEIAgAAAA==.',
As='Asmodeus:BAABNQAECoEZAAMDAAkKdRx6FACsAgADAAkKdRx6FACsAgAEAAEK7AZ6iQAoAAABNQAECgkJHAAFAD0fAA==.Asuna:BAAANQAECgYIDAAAAA==.',
At='Atilia:BAAANQADCgQIBAABNQAECggIIgAGAIwgAA==.Atmosfear:BAAANQADCgQIBAAAAA==.',
Ax='Axeldar:BAAANQAECgYIBgAAAA==.',
Az='Azucena:BAAANQAECgEIAQAAAA==.',
Ba='Bananos:BAABNQAECoElAAIHAAkK5hkVAwC4AgAHAAkK5hkVAwC4AgAAAA==.',
Be='Berrako:BAAANQADCgQIBAAAAA==.',
Bi='Billie:BAAANQAECgQIEwAAAA==.',
Bl='Blooddk:BAABNQAECoEoAAQHAAkKoyNnAACuAwAHAAkKbyNnAACuAwAIAAkKex77AgASAwAJAAMKtxAu7wC8AAABNQAFFAYIDQAKADUbAA==.',
Bo='Boojum:BAAANQAECgcIEAAAAA==.Booze:BAAANQADCggIDQAAAA==.',
Ch='Chachisimo:BAABNQAECoEaAAIKAAgKwyQVLAAsAwAKAAgKwyQVLAAsAwAAAA==.Chivasaurus:BAAANQAECgIIAgABNQAFFAUIBwALACoEAA==.',
Co='Covenant:BAAANQAECgQIBgAAAA==.',
Cr='Crunksmash:BAABNQAECoEcAAIMAAgKIA81KACtAQAMAAgKIA81KACtAQAAAA==.',
De='Demonbaked:BAAANQAECgIIAgABNQAFFAIIBAANAAAAAA==.Derpybômb:BAAANQADCgQIBAAAAA==.Dezyre:BAAANQAECgUICQAAAA==.',
Di='Dillon:BAAANQAECgEIAQAAAA==.',
Do='Donlobö:BAAANQADCggIDQAAAA==.Dora:BAABNQAECoEfAAIOAAgKcht+JAB7AgAOAAgKcht+JAB7AgAAAA==.Dorim:BAAANQAECgEIAQAAAA==.',
El='Elmono:BAACNQAFFIEKAAMKAAUKcwq5JAAfAQAKAAQKJAm5JAAfAQAPAAEKrw/yDABPAAA1AAQKgTQAAwoACQr5GARuAIwCAAoACQrfFwRuAIwCAA8ABQoOE3cZAAMBAAAA.Elohan:BAAANQAECgUIBQABNQAECgkJQAABABweAA==.',
Er='Erther:BAAANQAECgcJDQAAAA==.',
Fa='Far:BAACNQAFFIEHAAIQAAUKcQdECwBoAQAQAAUKcQdECwBoAQA1AAQKgSoAAxAACQpFHBckAOgCABAACQo8HBckAOgCABEABAqfFXALAAgBAAAA.',
Fe='Feralscale:BAAANQAECgIIAgAAAA==.',
Fl='Flashstep:BAAANQAECgQICAAAAA==.',
Fo='Foofiqt:BAABNQAECoEcAAMSAAcKFiOBIwDCAgASAAcKFiOBIwDCAgATAAMK+gyrFwCaAAAAAA==.Foxinahat:BAAANQADCgQIAgAAAA==.',
Fu='Fuddytotem:BAAANQAECgcIEgAAAA==.',
Fz='Fzy:BAAANQAECgEIAQABNQAECgcIEgANAAAAAA==.Fzydin:BAAANQAECgEIAgABNQAECgcIEgANAAAAAA==.',
Ge='Geus:BAAANQAECgIIAwAAAA==.',
Go='Goosejewce:BAABNQAECoEjAAMLAAkKvx1SIQDnAgALAAgKqB9SIQDnAgACAAIKnBTH3gCAAAAAAA==.',
Gr='Gremmil:BAAANQADCgQIBAAAAA==.Grimscar:BAAANQAECgYIBgAAAA==.',
Gw='Gweg:BAABNQAECoEpAAIQAAkKcCEVIQD2AgAQAAkKcCEVIQD2AgAAAA==.',
Ha='Hades:BAABNQAECoEtAAIQAAkKqyCrDABoAwAQAAkKqyCrDABoAwAAAA==.Halarda:BAACNQAFFIEIAAIQAAMKnxUUEQALAQAQAAMKnxUUEQALAQA1AAQKgSkAAhAACQpnIDofAP8CABAACQpnIDofAP8CAAAA.',
Ho='Hooves:BAACNQAFFIEPAAIUAAUKdQXDAgAZAQAUAAUKdQXDAgAZAQA1AAQKgTUAAhQACQqHFbwPACYCABQACQqHFbwPACYCAAAA.',
Ic='Icphunter:BAAANQADCggIBwAAAA==.',
Il='Ilythya:BAAANQADCgYIDwAAAA==.',
In='Infinus:BAAANQABCgUICQAAAA==.',
Is='Issolde:BAABNQAECoEYAAMVAAgKuhiyMQDgAQAVAAcKNxmyMQDgAQAWAAcKrxTlUACmAQABNQADCgcICAANAAAAAA==.',
Iz='Izthefoofi:BAAANQADCgYIBgABNQAECgcIHAASABYjAA==.',
Ja='Jaelana:BAABNQAECoEqAAMXAAgKGAlBFgDYAQAXAAgKGAlBFgDYAQACAAYKaBBziwA/AQAAAA==.Jazigor:BAAANQADCgcICgAAAA==.',
Jo='Josuboxxu:BAABNQAECoEcAAIYAAgK0CESBwD9AgAYAAgK0CESBwD9AgAAAA==.',
Ju='Judgyslap:BAAANQADCgUIBQAAAA==.',
Ka='Kamikozy:BAABNQAECoEzAAIKAAkKmiPKDACdAwAKAAkKmiPKDACdAwAAAA==.Kasharas:BAAANQAECgUIEwAAAA==.Kassandruh:BAAANQAECgYJCQAAAA==.Kazden:BAAANQAECgEIAQABNQAECggIGwAZAAEUAA==.',
Kh='Khain:BAAANQADCggICAAAAA==.Khealer:BAABNQAECoEWAAISAAcKixr7TgANAgASAAcKixr7TgANAgAAAA==.',
Ki='Kindi:BAAANQAECgQIDgAAAA==.Kitymeowmeow:BAACNQAFFIEPAAIaAAUKbCE+BADKAQAaAAUKbCE+BADKAQA1AAQKgTIAAhoACQrrJbABAMMDABoACQrrJbABAMMDAAAA.',
Kl='Klausnomi:BAACNQAFFIEHAAILAAUKKgTtDgBAAQALAAUKKgTtDgBAAQA1AAQKgTQAAgsACQofFv82AHQCAAsACQofFv82AHQCAAAA.',
Ko='Kowalzky:BAAANQADCgcIDQAAAA==.',
Kr='Krixer:BAAANQADCgYICQAAAA==.',
['Kà']='Kàndin:BAABNQAECoEbAAIZAAgKARS3NwAGAgAZAAgKARS3NwAGAgAAAA==.',
La='Lamorak:BAAANQAECgcIEgAAAA==.Lastdance:BAAANQAECgcIEQAAAA==.',
Li='Lilpsycho:BAAANQADCgQIBAAAAA==.',
Lo='Loldroodood:BAAANQADCgYIDwAAAA==.',
Lu='Lucia:BAAANQAECgUIDAAAAA==.',
Ma='Mafesto:BAAANQAECgcIEAAAAA==.Magnusbane:BAAANQADCgIIAgABNQAECgIIAwANAAAAAQ==.Malaqor:BAABNQAECoEiAAIGAAgKjCAyBADhAgAGAAgKjCAyBADhAgAAAA==.Manwe:BAAANQADCgQIBQAAAA==.Maylida:BAAANQADCgEIAQABNQAFFAYIDQAKADUbAA==.',
Mo='Monado:BAABNQAFFIEKAAIQAAUK+ROxBwCoAQAQAAUK+ROxBwCoAQAAAA==.Monkbluhd:BAAANQADCgQIBAAAAA==.Montedk:BAAANQAECgQIDAAAAA==.Moonjuice:BAABNQAECoEZAAIMAAgKoBOrIQDtAQAMAAgKoBOrIQDtAQAAAA==.Moosetameatu:BAABNQAECoEgAAIbAAgKESNpBAAjAwAbAAgKESNpBAAjAwAAAA==.Moscco:BAAANQADCgMIAwABNQAECgQICAANAAAAAA==.',
Na='Nahaii:BAAANQAECgMIBAABNQAFFAUIBwAQAHEHAA==.Nakskao:BAAANQADCggICgABNQAFFAYIDQAKADUbAA==.',
Ne='Necrogenesis:BAABNQAECoEvAAQOAAkKvhsUJQB3AgAOAAkKNxkUJQB3AgAWAAcKlBjHOAAcAgAVAAEKlArUkwAzAAAAAA==.Nelos:BAABNQAECoEjAAIcAAgKcRdSEgAsAgAcAAgKcRdSEgAsAgAAAA==.Neovisus:BAAANQADCgMIAwABNQAECgkJLwAOAL4bAA==.',
Ni='Nineline:BAAANQADCgQIBAABNQAECgcIFwAdAJojAA==.Nitroglycern:BAAANQAECgEIAQAAAA==.Nixhar:BAAANQAECgQIBAABNQAECgIIAwANAAAAAQ==.',
No='Nothelping:BAAANQADCgUIBQAAAA==.',
Od='Odjinn:BAAANQABCgYIBgAAAA==.',
Pa='Parrudo:BAAANQAECgEIAQAAAA==.',
Pi='Pinkember:BAAANQADCgQIBAAAAA==.',
Po='Poisontips:BAAANQADCgUIBQAAAA==.',
Sa='Sadler:BAAANQADCgMIAwAAAA==.Sake:BAAANQAECgYIDwABNQADCggIDQANAAAAAA==.Sakurá:BAAANQABCgMJAwABNQAECgMIAwANAAAAAA==.Sanctu:BAABNQAECoEcAAMFAAkKPR8vMwDfAgAFAAkKPR8vMwDfAgAeAAIKjglV7QBsAAAAAA==.',
Se='Setchyshock:BAAANQAECgQIBAAAAA==.',
Sh='Shulgin:BAABNQAECoEjAAIZAAgK4B3LIgCaAgAZAAgK4B3LIgCaAgAAAA==.',
Si='Silvia:BAAANQADCgUIBAAAAA==.',
Sk='Skankie:BAAANQAECgQIBQABNQAECggIGgAEAJ4dAA==.',
So='Sonari:BAAANQAECgQIBAAAAA==.',
Su='Superspike:BAACNQAFFIERAAIPAAUKmxmSAAChAQAPAAUKmxmSAAChAQA1AAQKgTIAAg8ACQqGJAUBAIgDAA8ACQqGJAUBAIgDAAAA.Surlockedin:BAABNQAECoEeAAQHAAgKfRW8EgD1AAAJAAYKhhI5lwB8AQAHAAQK6BK8EgD1AAAIAAMKww83QwCtAAAAAA==.',
Ta='Taekay:BAABNQAFFIEVAAIOAAYK0hw9BQAAAgAOAAYK0hw9BQAAAgAAAA==.Takamine:BAAANQAECgQIBQAAAA==.Talokan:BAAANQAECgIIAgABNQAECgMIAwANAAAAAA==.',
Te='Teletubi:BAAANQAFFAIIAgAAAA==.',
Th='Thehunter:BAAANQADCgEIAQAAAA==.Thezoolander:BAAANQABCgIIBAAAAA==.',
Tu='Tullkas:BAAANQADCgEIAQAAAA==.',
Va='Vanillarista:BAABNQAECoEcAAIfAAkKmiAMDwDqAgAfAAkKmiAMDwDqAgAAAA==.',
Ve='Vellara:BAAANQABCgIIAgAAAA==.',
Wa='Warmongering:BAAANQAECggIAQAAAA==.',
We='Wesdarian:BAAANQAECgIIAgAAAA==.',
Xi='Xirious:BAAANQAECgMIAwAAAA==.',
Ze='Zero:BAABNQAECoEpAAIDAAkK6h+JCwAYAwADAAkK6h+JCwAYAwAAAA==.',
['Ís']='Ísolde:BAAANQADCgcICAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
