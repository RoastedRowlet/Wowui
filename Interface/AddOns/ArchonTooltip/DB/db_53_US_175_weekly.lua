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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Warlock-Affliction','Mage-Arcane','DeathKnight-Blood','Rogue-Assassination','Paladin-Retribution','Priest-Holy','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Warrior-Arms','Shaman-Restoration','Hunter-BeastMastery','Shaman-Enhancement','Mage-Frost','Monk-Mistweaver','Warrior-Protection','Priest-Shadow','Druid-Restoration','Paladin-Protection',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgUIDAAAAA==.Aduhgall:BAAANQADCgUICQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECoEfAAMBAAgK5SKAGQC0AgABAAgKKSGAGQC0AgACAAcKQiJoEwCwAgAAAA==.Airbubble:BAAANQABCgEIAQAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECoElAAIDAAgKMBI6NQD0AQADAAgKMBI6NQD0AQAAAA==.Alex:BAABNQAECoEYAAIEAAgKzhE/HwAaAgAEAAgKzhE/HwAaAgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECgYIDQAFAAAAAA==.Allypally:BAAANQAECgYIDwAAAA==.',
Am='Amgrod:BAEANQADCgUJBQAAAA==.Amway:BAAANQAECgQIBAAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Andeyn:BAAANQADCgEIAgAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Ardur:BAAANQADCgUJBQAAAA==.Aremis:BAAANQAECgQIBQAAAA==.Arkhitype:BAAANQAECgYIDAAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggIAQAAAA==.',
As='Ashyslashy:BAAANQAECgcIDwAAAA==.Asur:BAAANQAECgUICwAAAA==.',
Au='Auracorusca:BAAANQAECgYIDwAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAAANQAECgYIDQAAAA==.',
Ba='Bajr:BAAANQAECgQIBgAAAA==.Bakura:BAABNQAECoEaAAIGAAgKHhoxAwCTAgAGAAgKHhoxAwCTAgAAAA==.Banker:BAAANQAECgYIDwAAAA==.Baroo:BAAANQADCgcIHwAAAA==.',
Be='Berko:BAABNQAECoEzAAIHAAgK4R73XwCRAgAHAAgK4R73XwCRAgAAAA==.Beyorne:BAAANQAECgEIAQAAAA==.',
Bh='Bhaang:BAAANQAECgMIBQAAAA==.',
Bi='Bigbear:BAAANQADCgYIBgABNQAECggIHQAIAA8lAA==.Bigbill:BAAANQADCggIEQAAAA==.Bigdeath:BAAANQAECgUIDgAAAA==.Biletooth:BAAANQADCgcIBgABNQAECgMIAwAFAAAAAA==.Bizco:BAAANQAECgYIEgAAAA==.',
Bj='Bjebo:BAABNQAECoEfAAIDAAgKcQ0ePQC8AQADAAgKcQ0ePQC8AQAAAA==.',
Bl='Bluffshot:BAAANQAECgYIEgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAFFAMIBgACAJsgAA==.Brynjalf:BAAANQAECgQIBwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïcho:BAAANQAECggIEAAAAA==.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cascadio:BAAANQAECgEIAQAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAAANQAECgIIAwAAAA==.',
Ch='Charjer:BAAANQAECgYIDAAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgQJBgAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcICQAFAAAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQAECgEIAQAAAA==.',
Cr='Cranks:BAAANQADCggICAAAAA==.Crashcake:BAABNQAECoEYAAICAAkKJR2GEgC7AgACAAkKJR2GEgC7AgAAAA==.Creakybones:BAAANQABCgIIAgAAAA==.Croager:BAAANQAECgQICAAAAA==.',
Cu='Cup:BAAANQAECgUIDgAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwAFAAAAAA==.',
Cy='Cywen:BAAANQADCggJCAABNQAFFAUICgAJAPcWAA==.',
Da='Daelaris:BAABNQAECoEXAAIHAAgK0x6MSADOAgAHAAgK0x6MSADOAgAAAA==.Damonoris:BAAANQAECgYIDQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQADCggICAAAAA==.Davegrôwl:BAAANQADCgEJAQABNQAECgMIAwAFAAAAAA==.',
De='Deadair:BAAANQADCgMIAwAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Dejavoid:BAAANQADCggICgAAAA==.Demonblades:BAAANQAECgYIEgAAAA==.Demonbreaker:BAAANQAECgYIEwAAAA==.Denarten:BAABNQAECoEaAAIKAAkKWSC1IAAQAwAKAAkKWSC1IAAQAwAAAA==.',
Di='Diotima:BAAANQADCgUICQAAAA==.Dirtymorris:BAAANQAECgcIEQAAAA==.Disrupt:BAAANQAECgIIAwABNQAECgQIBwAFAAAAAA==.',
Do='Dockevorkian:BAABNQAECoEoAAILAAkKXyDcDgAmAwALAAkKXyDcDgAmAwAAAA==.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAABNQAECoEbAAMMAAgKDxW2YQDjAQAMAAcKwhS2YQDjAQANAAIKvhQ1TQCBAAAAAA==.Doublebonus:BAAANQADCggICAABNQAFFAMIBgACAJsgAA==.Dougdk:BAABNQAECoEdAAIIAAgKDyWHCQBPAwAIAAgKDyWHCQBPAwAAAA==.',
Dr='Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgABNQAECgIIAgAFAAAAAA==.Drinnagon:BAAANQADCgcIBwABNQAECgkJGgAKAFkgAA==.Drinntellect:BAAANQAECgMIAwABNQAECgkJGgAKAFkgAA==.Drinnundead:BAAANQADCgEIAQABNQAECgkJGgAKAFkgAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAgAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYICwABNQAECgkJGAAOAMAjAA==.',
El='Elilla:BAAANQAECgYIDAAAAA==.Elkminster:BAAANQAECgIIAgAAAA==.Ellenaya:BAAANQAECggIDAAAAA==.Elorela:BAAANQADCgQIBAABNQAECgQICAAFAAAAAA==.',
En='Enjoy:BAACNQAFFIEGAAICAAMKmyDBBgAYAQACAAMKmyDBBgAYAQA1AAQKgSYAAwIACQo9JeACAKEDAAIACQrVJOACAKEDAAEACQrtIt8TAOUCAAAA.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Felnollid:BAABNQAECoEfAAMPAAkKRxm9GACRAgAPAAkKwxi9GACRAgAEAAUKiw2mPgD/AAAAAA==.Fenanigans:BAABNQAECoEcAAIJAAkKpyC2CAAdAwAJAAkKpyC2CAAdAwAAAA==.Fenquisition:BAAANQADCggICAABNQAECgkJHAAJAKcgAA==.',
Fi='Firebender:BAAANQADCgQIBQAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCgMIAwAAAA==.',
Fl='Fluffyhusky:BAAANQAECgYIEQAAAA==.',
Fo='Fontss:BAAANQAECgUIBgAAAA==.Fonyfish:BAAANQAECgUICQAAAA==.',
Fu='Fubina:BAEBNQAECoEgAAMQAAkKQBqMEQCSAgAQAAkKWRmMEQCSAgARAAIK5R1nHgClAAAAAA==.',
Fy='Fyjalla:BAAANQADCggJEAAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.',
Gi='Gilgaglaive:BAAANQAECggIDwAAAA==.Gilgämesh:BAACNQAFFIEHAAISAAQKuhD5EAA2AQASAAQKuhD5EAA2AQA1AAQKgSUAAhIACQrSId8fABUDABIACQrSId8fABUDAAAA.',
Gl='Glomah:BAAANQAECgYIEgAAAA==.Glorm:BAABNQAECoEYAAITAAgKQA/EWwCnAQATAAgKQA/EWwCnAQAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.',
Gr='Grabbyhands:BAAANQAECgMIAwAAAA==.Grantul:BAAANQAECgYIEgAAAA==.Grimthore:BAAANQADCgUICgABNQAECgYICwAFAAAAAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAAANQAECgMIAwAAAA==.',
Gu='Gulbhang:BAABNQAECoEbAAMMAAgKxR7XJAC8AgAMAAgKxR7XJAC8AgANAAEKXA+OagA5AAAAAA==.',
Hb='Hbkdx:BAAANQADCgIIAgAAAA==.',
He='Health:BAAANQAECgEIAQAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECggIHQAKAJEQAA==.Holyhammer:BAAANQAECgQIBAAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.',
Hu='Hujo:BAAANQAECgYIEAAAAA==.Hushpupi:BAAANQAECgQICAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQADCgEIAQAAAA==.Icesloth:BAAANQAECgYIDwAAAA==.',
Id='Idamarie:BAAANQAECgUICgAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAAANQAECgYICQAAAA==.',
In='Indecisa:BAAANQADCgUIBQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQADCgQIBwAAAA==.',
Ja='Jafuds:BAAANQAECgYIBgABNQAFFAUICwAIAPoZAA==.Jaggerss:BAAANQAECgEIAQABNQAFFAMIBgACAJsgAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAAANQAECgYICwAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAAANQAECgIIBAAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgQIBQAFAAAAAA==.',
Jo='Jordis:BAAANQADCgMIAwAAAA==.',
Ju='Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAAANQADCgEIAQAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Ke='Kerrster:BAAANQADCgQIBAAAAA==.',
Kh='Khármá:BAAANQAECgUICQAAAA==.',
Ki='Kicklocks:BAAANQAECgEIAQAAAA==.Kikuri:BAAANQAECgUIBQAAAA==.Killt:BAAANQAECgUIBgAAAA==.',
Ko='Koojoé:BAAANQAECgQIBAAAAA==.',
Ku='Kurzulan:BAAANQAECgYICgAAAA==.',
La='Laghles:BAABNQAECoElAAIUAAgK5yAxIgDWAgAUAAgK5yAxIgDWAgAAAA==.Laroes:BAAANQAECgEIAQABNQAECgYIEgAFAAAAAA==.Larua:BAAANQABCgQJBAAAAA==.',
Le='Lemanjá:BAAANQAECgIIAwAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAAANQAECgYIDgAAAA==.Limbless:BAAANQAECgUICAAAAA==.',
Lo='Loahealth:BAAANQAECgcICQAAAA==.Lockrocks:BAABNQAECoEXAAQGAAgKGhFuCQCZAQAGAAYK1BFuCQCZAQAMAAcK8AhNigBpAQANAAUKgwwGKgAWAQABNQAECgYICwAFAAAAAA==.Lockstar:BAAANQADCgQIBAAAAA==.Loko:BAAANQADCggIEQAAAA==.Lontra:BAAANQADCgQIBgAAAA==.Loozer:BAAANQAECgYICwAAAA==.Loralast:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAAANQAECgUIBwAAAA==.Mahlaan:BAABNQAECoEeAAIIAAgKDBknJwBNAgAIAAgKDBknJwBNAgAAAA==.Malakai:BAAANQADCgIIAgABNQAECgUICQAFAAAAAA==.Malekai:BAAANQAECgUJCAABNQAECgUICQAFAAAAAA==.Malyce:BAAANQAECgIIAgABNQAECgUICQAFAAAAAA==.Malzen:BAAANQADCgMIAwABNQAECgUICQAFAAAAAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIIBAAAAA==.',
Me='Meatcurtin:BAAANQADCgQIBAAAAA==.Meatlover:BAAANQAECgUJCAAAAA==.Mediocre:BAAANQAECgcJDwAAAA==.Meeshka:BAAANQAECgQICAAAAA==.Meraleona:BAAANQAECgcICgAAAA==.Methslinger:BAAANQAECgQIBwAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECgkJNQAKAMciAA==.Miltonroe:BAAANQADCggICAABNQAECggIHQAVAOoMAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgcIEwAFAAAAAA==.Moris:BAAANQAECgUIBgAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.Mosrael:BAAANQAECggIDAAAAA==.',
Ms='Mswizzlë:BAAANQAECgUJBQAAAA==.',
Mu='Muldah:BAABNQAECoEfAAMWAAgKWBOyEwArAQAHAAgKBxGDjwAfAgAWAAcKqQqyEwArAQAAAA==.',
Na='Nas:BAAANQAECgYIDgAAAA==.Nausicaa:BAAANQABCgYICQAAAA==.Nausicaä:BAAANQADCgUIBQAAAA==.Navie:BAAANQAECgYIDwAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECgYIDAAFAAAAAA==.Neø:BAABNQAECoEZAAMBAAgKRxf4PQDCAQABAAYKQhv4PQDCAQACAAcKiBFLNgCRAQAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQAECgQIBAAAAA==.Nightshala:BAAANQADCgYJBgAAAA==.',
No='Nokastakaj:BAAANQAECgYIDQAAAA==.Nollid:BAAANQADCgYIBgABNQAECgkJHwAPAEcZAA==.Nornyr:BAAANQADCgEIAQAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIDwAAAA==.',
Ny='Nymerias:BAAANQADCgYJDgAAAA==.Nyrrah:BAAANQAECgMIBAAAAA==.',
['Ná']='Nácht:BAAANQAECgIIAgAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Om='Omaticaya:BAAANQAECgUIEwAAAA==.Omèn:BAAANQADCgUIBQAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQAECgEIAQAAAA==.',
Ow='Owlbearcat:BAAANQAECgYICgABNQAECgcICQAFAAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgYIFAAAAA==.Paj:BAABNQAECoEYAAIHAAkKCRFOgQBBAgAHAAkKCRFOgQBBAgAAAA==.',
Pe='Pelledrusil:BAAANQADCgUIBQAAAA==.Peria:BAAANQADCgYIBgAAAA==.',
Pk='Pkalygos:BAAANQAECgYICQAAAA==.',
Pl='Pleione:BAAANQAECgUJBwAAAA==.',
Po='Portadave:BAAANQADCgYICAAAAA==.Powerstrokee:BAAANQAECgEIAQAAAA==.',
Pr='Preyforme:BAAANQAECgYIEAAAAA==.Prusik:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.',
Ps='Psychelone:BAAANQADCggIDgAAAA==.',
Pu='Puffshot:BAAANQADCggICAABNQAECgYIEgAFAAAAAA==.',
Qu='Quillan:BAAANQADCgUIDQABNQAECgcIDwAFAAAAAA==.',
Qy='Qyxh:BAAANQAECgUIEQAAAA==.',
Ra='Raine:BAAANQADCgUICAAAAA==.Rannath:BAAANQAECggIAwABNQAECggIDAAFAAAAAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Rehne:BAAANQAECgEJAQAAAA==.Rexhavoc:BAAANQAECgcJDgAAAA==.Rexion:BAAANQAECgEIAQAAAA==.',
Ri='Rigormortits:BAAANQADCgYIBgAAAA==.Ripre:BAAANQADCgUICwAAAA==.',
Ro='Rosary:BAAANQAECgUIDAAAAA==.Rosewoodren:BAAANQADCgcICwAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAAANQAECgYIDQAAAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBwABNQAECgQIBAAFAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEJAQABNQAECgMIAwAFAAAAAA==.Salitheion:BAAANQAECgIIAgAAAA==.Sapper:BAABNQAECoEiAAIXAAgK1x5hCQDGAgAXAAgK1x5hCQDGAgAAAA==.Sarn:BAAANQADCggICAAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shikí:BAAANQAECgEIAgAAAA==.Shladoran:BAAANQAECgUICQAAAA==.Shos:BAABNQAECoEeAAIYAAkKuxyVBQDZAgAYAAkKuxyVBQDZAgAAAA==.',
Si='Sinnister:BAAANQADCgYIBgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAECggIHQAIAA8lAA==.',
Sn='Snapdragyn:BAAANQADCggIBgAAAA==.Snorina:BAABNQAECoEcAAIZAAgKnx0iFACDAgAZAAgKnx0iFACDAgAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwAAAA==.Sosozen:BAAANQAECgUIDAAAAA==.',
Sp='Spirittoast:BAAANQAECgEIAQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAAANQAECgUIEwAAAA==.Stratovarius:BAAANQADCgYIBgAAAA==.',
Su='Sugouri:BAAANQAECggICAAAAA==.Supremacy:BAABNQAECoEZAAMMAAgKXyUKFgAFAwAMAAcK4iUKFgAFAwANAAEKzSGtWABjAAAAAA==.',
Sw='Sweetspot:BAAANQAECgQIBQABNQAECgYICwAFAAAAAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAAANQAECgYIDwAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECggIHAAZAJ8dAA==.Sylvii:BAABNQAECoEiAAIaAAgKnhIbHgDnAQAaAAgKnhIbHgDnAQAAAA==.',
Ta='Tabor:BAAANQAECgIIAgAAAA==.Taggz:BAAANQABCgQIBAAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAAANQAECgUIEgABNQAECgYIBgAFAAAAAA==.Tauryel:BAAANQAECgEIAQABNQAECgUICAAFAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECgcIBwAFAAAAAA==.',
Th='Thasarias:BAAANQAECgUIBwAAAA==.Themoosifer:BAACNQAFFIEPAAIEAAYKbBvkAQBBAgAEAAYKbBvkAQBBAgA1AAQKgSEAAgQACQpPIC4NAPMCAAQACQpPIC4NAPMCAAAA.Thyck:BAAANQAECgcIEQAAAA==.Thydis:BAABNQAECoEfAAIKAAgKfAoIkACaAQAKAAgKfAoIkACaAQAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAAANQAECgYIEgAAAA==.Ticklepickle:BAAANQAECgQICAAAAA==.',
To='Tooch:BAAANQADCggICAAAAA==.',
Tr='Trumalice:BAAANQADCgQICgAAAA==.',
Tu='Tulpa:BAAANQABCgQICgAAAA==.',
Un='Uncorrupted:BAABNQAECoEdAAMbAAkK6BKhGwC3AQAbAAgK+BShGwC3AQAKAAIKigSmSgE0AAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgQICAAFAAAAAA==.',
Va='Vaelm:BAAANQADCgIIAwAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAAANQAECgYICgAAAA==.Valjin:BAAANQADCgQIBAABNQAECgYICgAFAAAAAA==.Valuryan:BAAANQADCggICAABNQAECgYICgAFAAAAAA==.',
Ve='Velathila:BAAANQAECgEIAgAAAA==.',
Vi='Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAAANQAECgYICgAAAA==.',
Vo='Voidchris:BAABNQAECoEaAAIEAAgKCB4wEQC/AgAEAAgKCB4wEQC/AgAAAA==.Voidormu:BAAANQADCggIGwAAAA==.',
Wa='Warelf:BAAANQAECggIEwAAAA==.Warleck:BAAANQAECgEIAQAAAA==.',
Wh='Whodey:BAAANQAECgUICQAAAA==.',
Wi='Wisp:BAAANQADCgYICwAAAA==.',
Wy='Wylia:BAAANQAECgQIBAAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Yy='Yyirium:BAAANQADCgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAABNQAECoEfAAIUAAgKLw3PXwADAgAUAAgKLw3PXwADAgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwAFAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zuldave:BAAANQAECgYIEAAAAA==.',
Zy='Zylera:BAAANQAECgIIAgAAAA==.Zyphor:BAAANQADCggICAAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAAANQAECgUIEQAAAA==.',
['Ød']='Ødinson:BAAANQAECgEJAQAAAA==.',
['ßæ']='ßær:BAAANQAECgIJAgAAAA==.',
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
