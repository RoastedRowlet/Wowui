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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Rogue-Assassination','Warrior-Arms','Mage-Arcane','Unknown-Unknown','Druid-Balance','Priest-Holy','Hunter-BeastMastery','DeathKnight-Blood','Mage-Frost','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Warrior-Protection','Shaman-Enhancement','Warlock-Destruction','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Absol:BAABNQAECoEhAAMBAAkKTyGSAAB7AwABAAkKBCGSAAB7AwACAAgKeR8NIQDNAgAAAA==.',
Ac='Achilles:BAABNQAECoEcAAMDAAkKJBLmbQD4AQADAAkK/A/mbQD4AQAEAAMKAhODOwC7AAAAAA==.',
Ae='Aeon:BAAANQAECgEIAQAAAA==.Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAAANQAECgYIEQAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAAANQAECgQIBAAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQADCggJEAABNQAECggIMQAFAMAYAA==.',
Al='Alzaeryan:BAAANQAECgUICQAAAA==.',
Am='Amonet:BAAANQADCgcIFwAAAA==.',
An='Anamis:BAAANQAECgYIDgAAAA==.Angras:BAAANQAECgYIEwAAAA==.',
Ap='Aphalock:BAAANQAECgYIEwAAAA==.',
Ar='Ariûs:BAAANQAECgMIBQAAAA==.Arlin:BAAANQADCgcIDgAAAA==.Arlorian:BAABNQAECoEdAAIGAAcKOgzQMAClAQAGAAcKOgzQMAClAQAAAA==.Arrenn:BAAANQAECgMJBQAAAA==.Arrowsmites:BAAANQAECgYIDwAAAA==.',
As='Askelad:BAAANQAECgQICAAAAA==.',
Au='Aubani:BAAANQAECgYIDwAAAA==.',
Ay='Ayperos:BAABNQAECoEYAAIHAAcK8wsjmACAAQAHAAcK8wsjmACAAQAAAA==.',
Ba='Bakedpally:BAAANQAECgQICwAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIAwAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAAANQAECgUICgAAAA==.Beck:BAAANQAECgcIEwAAAA==.Bereth:BAAANQADCgcIFwAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECgcIFwAIAM0TAA==.Bikinibrenda:BAAANQAECgMIAwAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIFQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgcIEwAJAAAAAA==.Bluesummer:BAAANQADCgcIFAABNQAECgYIDwAJAAAAAA==.',
Bo='Bobeh:BAAANQADCggIFAABNQADCgEIAQAJAAAAAA==.Bolts:BAAANQABCgEIAQAAAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECoEXAAIIAAgK2h/sPADtAgAIAAgK2h/sPADtAgABNQADCgYIDwAJAAAAAA==.Borsam:BAAANQABCgYICAAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIAgAAAA==.Brom:BAAANQAECgQIBgAAAA==.Brutesse:BAAANQAECgQICAAAAA==.',
['Bè']='Bètflèch:BAAANQAECgEIAQAAAA==.',
['Bø']='Bøss:BAAANQADCgMIAwAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECoEcAAIKAAgKqxa4LQArAgAKAAgKqxa4LQArAgAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCgcIFAAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAAANQAECgUJCQAAAA==.',
Ch='Charlz:BAAANQADCggICAAAAA==.Charsifood:BAAANQAECgcIDQAAAA==.Chat:BAAANQAECggICAAAAA==.Cheatpriest:BAABNQAECoEdAAILAAgKuRG3SwDvAQALAAgKuRG3SwDvAQAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgMIBwAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECoEbAAIMAAcKKiPKIwDPAgAMAAcKKiPKIwDPAgAAAA==.Coldvengance:BAAANQAECgYIDgAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQAJAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQADCgYJCwAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAFFAMIAwAJAAAAAA==.',
Cy='Cymindel:BAABNQAECoEaAAINAAgKJRN8NQD1AQANAAgKJRN8NQD1AQAAAA==.Cyphr:BAAANQABCgYIBwAAAA==.',
Da='Dakotà:BAAANQAECgQICAAAAA==.Darc:BAAANQAECgMIBAAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQADCgYIBgAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQADCgUIBQAAAA==.',
De='Dejno:BAAANQAECgcIEgAAAA==.Deleted:BAAANQADCgUIBQABNQAECgcIEwAJAAAAAA==.Dethra:BAAANQAECgQICQAAAA==.Dezign:BAACNQAFFIENAAMOAAUKfyFbAgDIAAAIAAQKjSFVEwCJAQAOAAIKbyBbAgDIAAA1AAQKgScAAw4ACQrmJU4AANEDAA4ACQpYJU4AANEDAAgACQoSI1YmADADAAAA.',
Do='Dolgorukov:BAAANQAECgYIDgAAAA==.Dologony:BAAANQAECgUICQAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dragonmage:BAAANQAECgUICwAAAA==.Drakhan:BAAANQADCgIJAgAAAA==.Drakma:BAAANQAECgMIBQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECoEeAAIPAAgKNhcPCAAhAgAPAAgKNhcPCAAhAgAAAA==.Drmaker:BAAANQAECgEIAQAAAA==.Druj:BAEANQADCgcIBwABNQAECggIHAAKAKsWAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.',
['Dö']='Dötdötdead:BAAANQAECgMIAwAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQADCggIFwAAAA==.',
Ei='Eisheth:BAAANQADCgcIEgAAAA==.',
El='Elerav:BAAANQAECgMIAwAAAA==.Ellysiaa:BAAANQADCggJHwAAAA==.',
Em='Emmakyn:BAAANQAECgYIBwAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBAAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAAANQAECgUIBwAAAA==.',
Ez='Ezzka:BAAANQAECgcIEgAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgIIAgAAAA==.Farzix:BAAANQAECgUIDAAAAA==.Fatherdrew:BAAANQADCgcIBwABNQADCggIFQAJAAAAAA==.Façade:BAAANQAECgcIEwAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgEIBAAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAAANQAECgEIAgAAAA==.',
Fl='Flairadin:BAAANQAECgYIDwAAAA==.Flexo:BAAANQAECgEIAQAAAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAAANQAECgQICgAAAA==.',
Ga='Garythenpc:BAAANQADCgcIFwAAAA==.',
Ge='Genericeric:BAAANQADCgcICAAAAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.',
Gl='Glacialkitty:BAAANQAECgUIDgAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAQAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECgcIFwAIAM0TAA==.Goudanight:BAAANQADCgIIAgABNQAECgcIFwAIAM0TAA==.Goudatime:BAAANQAECgUIBwABNQAECgcIFwAIAM0TAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQADCgcIFgAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Ha='Hakibalboa:BAABNQAECoEbAAIQAAgKegybEQCHAQAQAAgKegybEQCHAQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAAANQAECgYIDwAAAA==.',
He='Heis:BAAANQADCgcIDgAAAA==.Hellboii:BAAANQAECgcIDQAAAA==.Heyitsrat:BAAANQAECgQICgAAAA==.',
Ho='Hollowtips:BAAANQADCgQIBAAAAA==.Holo:BAABNQAECoEiAAMRAAkKdCNYFAAsAwARAAgKkCNYFAAsAwASAAkKHw/kVQC9AQAAAA==.Housemom:BAAANQAECgQIBAAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCgQIBQAAAA==.',
Ic='Icculus:BAAANQAECgIIAwAAAA==.',
Im='Imaresmashy:BAAANQABCgIIAQABNQAECgIIAgAJAAAAAA==.Iminyou:BAAANQAECgYIEwAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECggIIAAHAMwVAA==.',
Ja='Jaenei:BAAANQAECgMIBAAAAA==.Janet:BAAANQADCgYIBgABNQAECggIGwALALgkAA==.',
Je='Jeeb:BAABNQAECoEZAAIIAAcKQw9zwACzAQAIAAcKQw9zwACzAQAAAA==.',
Ji='Jinxta:BAAANQAECgYIDQAAAA==.',
Jo='Joansnow:BAAANQADCggICgAAAA==.Joeeo:BAABNQAECoEbAAMLAAgKRxe5OwAzAgALAAgKRxe5OwAzAgATAAcKiwfpMABJAQAAAA==.',
Ju='July:BAAANQAECgMIBAAAAA==.Julytonidas:BAAANQAECgcICAAAAA==.Jurac:BAAANQADCgUIBQAAAA==.',
Ka='Kaimargonar:BAAANQAECgIIAwAAAA==.Kaitoi:BAAANQAECgUIBwAAAA==.Kamakizeg:BAAANQAECgQICQAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQADCgUIBQABNQAECgcIEgAJAAAAAA==.Katimalice:BAAANQADCgQJDQAAAA==.',
Ke='Keathry:BAAANQADCgcICwAAAA==.Keyzeus:BAAANQAECgIIAwAAAA==.',
Kh='Khas:BAAANQADCgMIAwAAAA==.Khui:BAABNQAECoEjAAMUAAkKniOKAgB2AwAUAAkKniOKAgB2AwAVAAUK6R6bJgCKAQAAAA==.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgEIAQAAAA==.',
Kn='Knìghtmàrè:BAABNQAECoEgAAMWAAkKDiO9DAArAwAWAAkKnCK9DAArAwANAAQKOxwCXwAuAQAAAA==.',
Ko='Koltharaz:BAABNQAECoEhAAIXAAkKxhp/CADKAgAXAAkKxhp/CADKAgAAAA==.Korloff:BAAANQADCggIEwABNQAECgIIAwAJAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazylock:BAAANQAECgQIBgAAAA==.',
Ku='Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgYICwAAAA==.',
Ky='Kylar:BAAANQADCgMIBAAAAA==.',
La='Lateralus:BAABNQAECoEeAAIWAAgKfCLRGAC6AgAWAAgKfCLRGAC6AgAAAA==.Latt:BAAANQAECgIIAgABNQAECggJHgAWAHwiAA==.Lawluss:BAAANQAECgQICwAAAA==.',
Le='Legacyshot:BAAANQAECgIIAgAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIAwAAAA==.Lightguard:BAAANQADCgcIBAAAAA==.Lighthouse:BAABNQAECoEeAAMYAAgKkRXoOABDAgAYAAgKkRXoOABDAgADAAIKNAWtKwFaAAAAAA==.Lileth:BAAANQADCggIEAAAAA==.',
Lo='Lolhahabaha:BAAANQAECgIIAgAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQADCgMIAwAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAAANQAECgcIEwAAAA==.',
['Lï']='Lïllïth:BAAANQAECgYICwAAAA==.Lïly:BAAANQAECgIIAgABNQAECgIIAgAJAAAAAA==.',
['Ló']='Lóla:BAAANQAECgYIEAAAAA==.',
Ma='Madeah:BAABNQAFFIELAAIGAAUK0hJVAwCpAQAGAAUK0hJVAwCpAQAAAA==.Madforge:BAABNQAECoEYAAISAAgKThWqQwAFAgASAAgKThWqQwAFAgAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggIAwAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECoEcAAIIAAgK4xqlZwB+AgAIAAgK4xqlZwB+AgAAAA==.Mariacuras:BAAANQAECgYIEAAAAA==.Marijwana:BAAANQAECgMIBgAAAA==.Martis:BAAANQAECgYIEgAAAA==.Marynne:BAAANQAECgUICwAAAA==.Mazuko:BAAANQAECgYIDgAAAA==.',
Me='Mecandry:BAABNQAECoEcAAIMAAgKAhQbSABJAgAMAAgKAhQbSABJAgAAAA==.Mecks:BAAANQADCgUIBgAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAAANQAECgQICAAAAA==.Meranda:BAABNQAECoEXAAIIAAcKzROnsADWAQAIAAcKzROnsADWAQAAAA==.Merriklade:BAAANQAECgUICwAAAA==.Merrikoid:BAAANQAECgQIBgAAAA==.',
Mi='Mico:BAAANQAECgEIBAAAAA==.',
Mo='Morbidstyle:BAAANQADCgcIDAABNQAECggIGgARABwQAA==.Morgoth:BAABNQAECoEdAAICAAgKxBdVQgBLAgACAAgKxBdVQgBLAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECoEZAAINAAcKlB5kJQBYAgANAAcKlB5kJQBYAgABNQABCgQIBgAJAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECggIHAAKAKsWAA==.Mythundirus:BAAANQAECgUICwAAAA==.',
['Mà']='Màrli:BAAANQAECgYIEQAAAA==.',
['Mâ']='Mâgs:BAAANQAECgYIDwAAAA==.',
Na='Nakasid:BAABNQAECoEYAAMLAAgK0A5YVQDHAQALAAgK0A5YVQDHAQATAAUKCAd2PgDhAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgIIBQAAAA==.Neins:BAAANQADCgYIEAABNQAECgIIBQAJAAAAAA==.Nevaehstar:BAABNQAECoEjAAIIAAgKkQ+RngD9AQAIAAgKkQ+RngD9AQAAAA==.',
Ni='Nijun:BAEANQAECgYIDwAAAA==.Nik:BAAANQADCggIIwAAAA==.Nikolia:BAAANQAECgQICgAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAAANQAECgQIBwAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAQICAAZAIQWAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgUIBQABNQAECgkJIQABAE8hAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECggIHAAMAAIUAA==.',
Ov='Overtime:BAAANQADCggICgAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCgEIAQAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQABCgIIAgAAAA==.',
Po='Polog:BAAANQAECgIIAgABNQAECgcIEwAJAAAAAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkchopw:BAAANQABCgQIBAAAAA==.Porkribs:BAAANQAECgYIDwAAAA==.',
Pu='Puca:BAAANQADCgcIFwAAAA==.Pumdmuc:BAAANQAECgQICgABNQAECggIHgASAPccAA==.Punchymcheal:BAAANQAECgIIAgABNQAECggIIAALANkeAA==.',
Qu='Quikglaives:BAAANQAECgEIAQAAAA==.Quille:BAAANQAECgYIEwAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgcIDwAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Redrek:BAAANQADCgYIGAAAAA==.Redshunter:BAAANQADCgQIBAAAAA==.Redwinter:BAAANQAECgYIDwAAAA==.Reikisong:BAAANQADCggICQAAAA==.Reiluune:BAAANQADCgQIAwABNQAECgYIEAAJAAAAAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECoEgAAIaAAkKCCabAADlAwAaAAkKCCabAADlAwAAAA==.',
Ri='Riqua:BAAANQAECgIIAwAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQABCgQIBQAAAA==.Roxies:BAAANQAECgMIAwAAAA==.',
Rp='Rpg:BAABNQAECoEVAAIIAAgKOxmjZwB+AgAIAAgKOxmjZwB+AgAAAA==.',
Ru='Runes:BAAANQAECgEIAgAAAA==.',
Sa='Saeti:BAABNQAECoEeAAUbAAkKviChAwAlAwAbAAgKDCOhAwAlAwAFAAIKMxLPTAB3AAAaAAEKxB8INgBbAAAKAAEKTA4mlgArAAAAAA==.Santhaenis:BAAANQADCgIIAgAAAA==.Sapplesauce:BAAANQADCggICQAAAA==.',
Se='Seethrowwar:BAABNQAECoEfAAMHAAkKgR/6IwADAwAHAAkKQR/6IwADAwAcAAYKcxZKEwCUAQAAAA==.Senbit:BAAANQAECgUIDQAAAA==.Serenìty:BAAANQAECgUIDAAAAA==.Seresin:BAABNQAECoExAAMFAAgKwBhsFABeAgAFAAgKwBhsFABeAgAKAAUKNwjBaQDQAAAAAA==.',
Sh='Shadý:BAAANQAECgQICgAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgcIEwAJAAAAAA==.Shortwarrior:BAAANQAECgMIBgAAAA==.',
Si='Sianu:BAAANQADCgcIBwABNQAECgUICwAJAAAAAA==.Sidraya:BAAANQAECgEIAgAAAA==.Silent:BAABNQAECoEgAAIHAAgKzBUaaQAKAgAHAAgKzBUaaQAKAgAAAA==.Silverserqet:BAAANQAECgUIBwAAAA==.',
Sm='Smileyriley:BAAANQADCgUIBQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECggIFQAIADsZAA==.',
So='Sonbit:BAAANQADCggJDwAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIBgAAAA==.Soulber:BAAANQAECgMIBAAAAA==.',
Ss='Ssenbit:BAAANQADCgcIDgAAAA==.',
St='Sternhoof:BAAANQABCgMIAwAAAA==.Stigma:BAAANQADCggIFQAAAA==.Stylos:BAAANQAECgYICQAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.',
Sw='Swowtitbang:BAAANQAECgMIBAAAAA==.',
Te='Tegbolt:BAABNQAECoEYAAMRAAgKgBOsSwD4AQARAAgK1xCsSwD4AQAdAAcKHhH8EwDTAQAAAA==.Tekko:BAABNQAECoEZAAIaAAcKZhnbDQAMAgAaAAcKZhnbDQAMAgAAAA==.Tempestrike:BAAANQAECgYIBgAAAA==.',
Th='Theholymatt:BAABNQAECoEeAAIYAAgKkyTKCwBKAwAYAAgKkyTKCwBKAwAAAA==.Thendari:BAABNQAECoEeAAIeAAYK9QuFIQBQAQAeAAYK9QuFIQBQAQAAAA==.Theodus:BAAANQAECgYIEwAAAA==.Therayen:BAAANQADCgYJCwAAAA==.',
Ti='Tiferis:BAABNQAECoEiAAIYAAkKZRs9GwDcAgAYAAkKZRs9GwDcAgAAAA==.Tigerclawss:BAAANQADCgUICQAAAA==.Tislam:BAAANQAECgMIBAAAAA==.',
To='Tobiquer:BAABNQAECoEZAAILAAcKoiKyHQDFAgALAAcKoiKyHQDFAgAAAA==.Torolf:BAAANQADCggIEwAAAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECoEgAAIRAAkKuR3aFwARAwARAAkKuR3aFwARAwAAAA==.',
Ts='Tsonokwabain:BAAANQAECgQICgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAAANQAECgYIDgAAAA==.Tyranastrasz:BAABNQAECoEcAAQXAAgKdQYpGwBbAQAXAAgKdQYpGwBbAQAfAAIK8wK+PgBNAAAgAAEKTQCTIAANAAAAAA==.Tyye:BAAANQAECgYIDAAAAA==.',
['Tâ']='Tâjik:BAAANQAECgcIDgAAAA==.',
Ul='Ulquiorra:BAABNQAECoEhAAMhAAkKRhvdEgCpAgAhAAgKah3dEgCpAgAPAAMKxwp4GwCVAAAAAA==.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBAAAAA==.Valgavoth:BAAANQAECgcIDgAAAA==.Vanthion:BAAANQADCgIIAgAAAA==.',
Ve='Velara:BAAANQAECgQIBAAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQAJAAAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgIIAgAAAA==.',
Vo='Voidlighter:BAABNQAECoEgAAILAAgK2R7UIAC0AgALAAgK2R7UIAC0AgAAAA==.Volundr:BAAANQAECgYIDwAAAA==.Vonvaughan:BAAANQAECgIIAgABNQAECgIIAgAJAAAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECggIJAARAMAgAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECoEWAAIGAAYKVxoVKADmAQAGAAYKVxoVKADmAQAAAA==.',
We='Weabe:BAAANQAECgIIAwAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQADCgQJBAABNQAECgYIDwAJAAAAAA==.',
Wo='Wolfgarou:BAAANQABCgIIAgAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECoEeAAIMAAgK6QiicQDSAQAMAAgK6QiicQDSAQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAAANQAECgYIDwAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQADCgYIDwAAAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECoEcAAIDAAkKYxO2WgAyAgADAAkKYxO2WgAyAgAAAA==.',
Za='Zaraeliana:BAAANQAECgMJBAAAAA==.Zarastraza:BAAANQAECgYIEAAAAA==.',
Ze='Zephnor:BAAANQAECgYICwAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQADCgQIBAAAAA==.',
Zu='Zulrok:BAAANQAECgYIDwAAAA==.',
['Áb']='Ábsurd:BAAANQADCggIEQABNQABCgIIAQAJAAAAAA==.',
['Ðr']='Ðre:BAAANQAECgMIAwAAAA==.',
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
