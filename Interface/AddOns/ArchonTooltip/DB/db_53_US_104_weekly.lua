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

local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Mage-Arcane','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Paladin-Protection','Priest-Holy','Priest-Shadow','Priest-Discipline','DemonHunter-Devourer','DeathKnight-Unholy','DemonHunter-Vengeance','Warrior-Arms','Shaman-Elemental','DeathKnight-Frost',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acherona:BAAANQABCgQIBAAAAA==.Acuminada:BAAANQADCgIIAgAAAA==.Acuna:BAAANQAECgMIBwAAAA==.',
Ad='Adison:BAAANQADCgYIBgAAAA==.',
Af='Affliction:BAAANQAECgMIBQAAAA==.',
Ai='Airz:BAAANQAECgIIBAAAAA==.',
Ak='Akâkiôs:BAAANQAECgIIAwAAAA==.',
Al='Aladorman:BAAANQADCggIFAAAAA==.Alamo:BAAANQAECgEIAQAAAA==.Albertlin:BAAANQAECgQIBgAAAA==.Alexinar:BAAANQADCgcICgAAAA==.',
Am='Amakuagsak:BAAANQADCggIGwAAAA==.Amicus:BAAANQAECgEIAQAAAA==.Ampmage:BAAANQAECgIIAwAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.',
Ap='Apollo:BAAANQAECgQICAAAAA==.Apolynnæ:BAAANQAECgYIEAAAAA==.',
Ar='Araniss:BAAANQAECgQIBAAAAA==.Arasthel:BAAANQADCgcIDAAAAA==.Aratrath:BAAANQAECgUIDAAAAA==.Aryasilly:BAAANQAECgQIBgAAAA==.',
As='Asdi:BAAANQADCggIOwAAAA==.Ashe:BAABNQAECoEgAAIBAAkJuiSHAQC2AwABAAkJuiSHAQC2AwAAAA==.',
At='Attabubble:BAAANQAECgEIAQABNQAECggIEgACAAAAAA==.Attaraxia:BAAANQAECggIEgAAAA==.',
Au='Aurelith:BAAANQADCgIIBAAAAA==.',
Av='Aviarra:BAAANQABCgUIBwAAAA==.',
Ay='Ayroon:BAAANQADCgUICAAAAA==.',
['Aé']='Aéquítas:BAAANQAECgIIAgAAAA==.',
Ba='Bamfbutcher:BAAANQAECgUICAAAAA==.Barent:BAAANQADCgYIDAAAAA==.Barrimen:BAAANQAECgUICgAAAA==.Bartolomew:BAAANQAECgMIBgAAAQ==.Bartonella:BAAANQADCgIIAgABNQADCgYICAACAAAAAA==.',
Be='Bedemere:BAAANQAECgQIBgAAAA==.Beepers:BAAANQAECgYIDgAAAA==.Behodahlia:BAAANQAECgMIAwAAAA==.Belfie:BAAANQAECgQIBAAAAA==.Berrylla:BAAANQADCgIIAgAAAA==.',
Bi='Bigmakk:BAAANQAECgQIBwAAAA==.Bimzelx:BAAANQADCgcIEAAAAA==.Bitterblood:BAAANQAECgIIBAAAAA==.',
Bl='Blastgamer:BAAANQADCggIFgAAAA==.Blondebeard:BAAANQAECgYICgAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAAANQAECgUIBwAAAA==.',
Br='Bragontix:BAAANQAFFAEIAQAAAA==.Bravehearth:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.Brewvoke:BAAANQAECgUICQAAAA==.Brightxan:BAAANQAECgUICwAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECgUICgACAAAAAA==.Bubbahunter:BAAANQAECgUICgAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECgUICgACAAAAAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAABNQAECoEXAAIDAAkJMRd2RgB7AgADAAkJMRd2RgB7AgAAAA==.Buddhabum:BAAANQAECgEIAQAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAAANQAFFAIIBAAAAA==.Bussdefense:BAAANQADCgYIEAAAAA==.Butterrs:BAAANQAFFAEIAQAAAQ==.Butterz:BAAANQAECgEIAgABNQAFFAEIAQACAAAAAA==.',
Ca='Caleian:BAAANQADCgYIEAAAAA==.Caloren:BAAANQAECgQICAAAAA==.Caorou:BAAANQADCgUIBwAAAA==.',
Ch='Charlyte:BAAANQAECgUICQAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Cr='Crysinia:BAAANQABCggIDQAAAA==.',
Cu='Cuigy:BAAANQAECgMIAwAAAA==.',
Cy='Cyriene:BAAANQAECgEIAQAAAA==.Cyril:BAAANQADCgQIBAABNQAECgIIAgACAAAAAA==.',
Da='Dalio:BAAANQADCgcICAAAAA==.Danté:BAAANQAECgEIAQAAAA==.Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAAANQAECgMIBAAAAA==.',
Dd='Ddeathchura:BAAANQAECgMIBAAAAA==.',
De='Deactrim:BAAANQAECgMIBQAAAA==.Dema:BAAANQADCgQIBAAAAA==.Dendrada:BAAANQAECgMIBAAAAA==.Deuce:BAAANQAECgMIAwAAAA==.',
Di='Dizimo:BAAANQAECgQIAwAAAA==.',
Do='Dogmeat:BAAANQAECggIEwABNQAFFAMIBQAEANcSAA==.Dotisa:BAAANQADCggICAAAAA==.',
Dr='Dragonlex:BAAANQADCgcIBwAAAA==.Drakeshadows:BAAANQADCgIIAgAAAA==.Drchivago:BAAANQADCgYIBgAAAA==.',
Du='Duna:BAAANQAECgEIAQAAAA==.Dungoofed:BAAANQADCgUICQAAAA==.Duvidressra:BAABNQAECoEWAAMFAAgJ+xKgAwADAgAFAAcJ2hSgAwADAgAGAAIJ1QdkpgB2AAAAAA==.',
Dx='Dxmvn:BAAANQADCgQIBQAAAA==.',
Ed='Edisonn:BAABNQAECoEUAAMHAAgJFw8UIAA5AQAGAAUJtQ4ZYwBFAQAHAAUJBRAUIAA5AQAAAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgUICgAAAA==.Elentisa:BAAANQADCggIEAAAAA==.Elghinn:BAAANQAECgQICAAAAA==.Elissaria:BAAANQADCgQIBAAAAA==.Ellastrasza:BAAANQAECgQICQAAAA==.Ellie:BAAANQAECgIIAgAAAA==.Elroy:BAAANQAECgUICgAAAA==.',
Em='Emernantus:BAAANQAECgQIBgAAAA==.',
Er='Erazar:BAAANQAECgUICwAAAA==.',
Es='Espy:BAAANQAECgMIBAAAAA==.',
Eu='Eunbyeol:BAAANQAECgUICgAAAA==.',
Ev='Evee:BAAANQABCgQIBAAAAA==.',
Fa='Faeria:BAAANQAECgIIBAAAAA==.Fatcritties:BAAANQAECgIIAgAAAA==.Fatnchunkydk:BAAANQAECgIIAgAAAA==.',
Fe='Feeblemind:BAAANQAECgMIAwAAAA==.Feli:BAAANQAECgMIAwAAAA==.Femboi:BAAANQADCggIDgAAAA==.Fender:BAAANQAECgIIAgAAAA==.',
Ff='Ffugntotems:BAAANQADCgcICwAAAA==.Ffviitifa:BAAANQADCgcICwAAAA==.',
Fi='Fingertoes:BAAANQAECgUIDAAAAA==.Fizzlerazz:BAAANQADCgUIBQAAAA==.',
Fl='Flatulatta:BAAANQAECgQICAAAAA==.Flyciful:BAAANQADCgcIBwAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQADCgUIBgABNQAECgIIAwACAAAAAA==.Foxehh:BAAANQABCgUIBwAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAAANQAFFAEIAQAAAA==.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCgUICQAAAA==.Frodowagons:BAAANQAECggICAAAAA==.Frostpie:BAAANQAECgYIBgAAAA==.',
Fu='Fuglybaby:BAAANQADCgUICQAAAA==.Fuhenhenka:BAAANQADCggICgAAAA==.',
Fw='Fwakos:BAAANQADCggIEwAAAA==.',
Ga='Gakmonk:BAAANQADCgYIBgABNQAECgQICAACAAAAAA==.Gakpaladin:BAAANQAECgQICAAAAA==.Galthul:BAAANQADCgUIBQABNQAECgQICAACAAAAAA==.Garfyaz:BAAANQADCgYICwAAAA==.',
Gd='Gdlez:BAAANQADCgcIDAAAAA==.',
Ge='Gethael:BAAANQADCgIIAgAAAA==.',
Go='Goatroth:BAAANQADCggIDgAAAA==.Golorious:BAAANQAECgYIDgAAAA==.Goododie:BAAANQAECgEIAQAAAA==.',
Gr='Grenas:BAAANQABCgMIBQAAAA==.Grippyweasle:BAAANQAECgQIBgAAAA==.Grovelly:BAAANQABCggIEAAAAA==.Growlius:BAAANQADCgcIBwABNQAECgQIBAACAAAAAA==.',
Gu='Gulaken:BAAANQAECgIIBAAAAA==.Guseva:BAAANQAECgEIAQAAAA==.Guttershark:BAAANQAECgYIDwAAAA==.',
Ha='Hafnia:BAAANQADCgYICAAAAA==.Halliday:BAAANQADCggIHAAAAA==.Haoasakura:BAAANQAECgcIEAAAAA==.Haylo:BAAANQAECgIIAwAAAA==.',
He='Headshop:BAAANQADCgYIBgAAAA==.Healzforfood:BAAANQADCgcICAAAAA==.Heap:BAAANQAECgMIAwABNQAECgYICgACAAAAAA==.Heartlight:BAAANQADCgMIAwAAAA==.Heavyreign:BAAANQADCgQIBwAAAA==.Helicobacter:BAAANQADCgMIAwAAAA==.Hewnoshaqa:BAAANQAECgQIBAAAAA==.Hexorcist:BAABNQAECoEWAAIIAAgJ0x1ZGACTAgAIAAgJ0x1ZGACTAgAAAA==.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAAANQADCggIDwABNQAECgMIAwACAAAAAA==.',
Ho='Holyanne:BAAANQADCgQIAgAAAA==.Holyspanks:BAAANQADCgYIBgABNQAECgYIDQACAAAAAA==.Horous:BAAANQADCggICAAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntrlicious:BAAANQAECgMICAAAAA==.Husqvarnna:BAAANQADCgUIBQAAAA==.',
Id='Idoshiftwork:BAAANQAECgYIDgAAAA==.Idunno:BAAANQADCgYICQAAAA==.',
Ik='Ikazuchi:BAAANQAECgQIBQAAAA==.',
Il='Illcutabish:BAAANQAECggIEAAAAA==.Illtank:BAAANQAECgMIAgAAAA==.',
Im='Imatankin:BAAANQAECgEIAQAAAA==.Imk:BAAANQAECgMIBAAAAA==.',
Io='Iock:BAEANQAECgUIBQAAAA==.',
Ir='Ironarms:BAAANQAECgYIDQAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAAANQAECgYIBwAAAA==.Jessd:BAAANQADCgcIBwAAAA==.',
Ji='Jinuoo:BAAANQADCgQIBAAAAA==.',
Jo='Johnwarrior:BAAANQAECgQICgAAAA==.Jorrix:BAAANQAECgIIBAAAAA==.',
Ju='Juduspriestt:BAAANQAECgIIAwAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgYIDAAAAA==.',
Ka='Kaaeko:BAAANQAECgUICwAAAA==.Kalerito:BAAANQAECgQICAAAAA==.Kallythea:BAAANQADCggICAAAAA==.Kardie:BAAANQADCgQIBAABNQAECgUICwACAAAAAA==.Karl:BAAANQADCggIEwAAAA==.Kaserr:BAACNQAFFIEJAAMJAAUJdhNVAwBfAQAJAAQJIg1VAwBfAQAKAAIJkxdmAwC/AAA1AAQKgSAAAwkACQkSJbwDADoDAAkACAlIJbwDADoDAAoAAwmII7EmADABAAAA.Kayserdh:BAAANQAECgUICAAAAA==.Kazaf:BAAANQAECgQICQAAAA==.Kazarian:BAAANQADCgEIAQAAAA==.',
Ke='Kebru:BAAANQAECgQIBgAAAA==.Keitrek:BAAANQAECgQICAAAAA==.Kelthias:BAAANQADCgYICwAAAA==.Keyen:BAAANQAECgMIBAAAAA==.',
Ki='Kibalion:BAAANQADCggIEgAAAA==.Killbent:BAAANQADCgYIFAAAAA==.Kinnky:BAAANQAECgIIAgAAAA==.Kino:BAAANQAECgIIAgAAAA==.Kitn:BAAANQABCgQIBAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAAANQAECgQICAAAAA==.Krispy:BAAANQADCgcIBwABNQAECgUIDAACAAAAAA==.',
Ks='Ksp:BAAANQADCgQIBQAAAA==.',
Ku='Kugamoo:BAAANQAECgYIDgAAAA==.Kulgan:BAAANQAECgcIEAAAAA==.Kurgen:BAAANQAECgEIAQAAAA==.Kuroda:BAAANQADCggIDwAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.',
La='Lamiah:BAAANQAECgEIAQAAAA==.Lauadia:BAAANQADCgUIBQAAAA==.',
Lc='Lckdown:BAAANQAECggICAAAAA==.',
Le='Legomyegolas:BAAANQADCgYIBgAAAA==.',
Li='Lightsocket:BAAANQADCgUIBQAAAA==.Livingkntpib:BAAANQADCggICAAAAA==.',
Lo='Loden:BAAANQAECgcIDAAAAA==.Lodez:BAAANQAECgYICQAAAA==.Loktarhogar:BAAANQAECgUIBQAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAAANQAECggIBAAAAA==.',
Lu='Luckyboi:BAAANQAECgcIEAAAAA==.Lumeria:BAAANQAECgIIAwAAAA==.Lumina:BAAANQAECgQIBwAAAA==.Lusciifi:BAABNQAECoEfAAMLAAkJjyRwAwDBAwALAAkJjyRwAwDBAwAMAAMJPxZiKwChAAAAAA==.',
Ly='Lykie:BAAANQAECgcIEQAAAA==.Lynxic:BAAANQADCgQIBwABNQADCgUIBQACAAAAAA==.Lyone:BAAANQAECgQIBQAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lú']='Lúvaa:BAAANQAECgYIEQAAAA==.',
Ma='Macavity:BAAANQADCgMIAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQAECgQIBAAAAA==.Magicwoman:BAAANQADCggIDgAAAA==.Magikkisback:BAAANQADCggIDQAAAA==.Magsh:BAAANQADCggIGQAAAA==.Mandorius:BAAANQAECgMIAgAAAA==.Maphra:BAAANQADCggICAABNQAECgMIAwACAAAAAA==.Marcos:BAAANQADCgIIAgAAAA==.Maverickdog:BAAANQAECgcIEgAAAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQADCgcIEgACAAAAAA==.Meekzz:BAAANQADCggICQAAAA==.Meeshie:BAABNQAECoEZAAQNAAgJ1g1TOwClAQANAAgJ1g1TOwClAQAOAAQJdQnwLgDfAAAPAAEJjAbCGgAwAAAAAA==.Melodrop:BAAANQAECggIBQAAAA==.',
Mi='Mihawk:BAAANQADCgEIAQABNQAECgUIDAACAAAAAA==.Mikexfire:BAAANQAECgIIBQAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Mildchaos:BAAANQAECgIIAQAAAA==.Mishima:BAAANQAECggICAAAAA==.Misspell:BAAANQADCggIFAAAAA==.Miznewbooty:BAAANQAECgYIDgAAAA==.',
Mo='Moochella:BAAANQAECgMIAwAAAA==.Moojestic:BAAANQADCggIDwAAAA==.Moonq:BAAANQAECgMIBAAAAA==.Moosie:BAAANQAECgQIBwAAAA==.Mooska:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Moxflip:BAAANQAECgcIBwAAAA==.Mozzers:BAAANQADCgcIBwAAAA==.',
Mu='Muertenegra:BAAANQADCgUIBQABNQAECgIIAwACAAAAAA==.Muffy:BAAANQAECgQIBQAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Myllakura:BAAANQAECgIIAgAAAA==.Mythnarra:BAABNQAECoEZAAIQAAkJ+SDvBABjAwAQAAkJ+SDvBABjAwAAAA==.',
['Mä']='Mäomäo:BAAANQADCgMIAwAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAABNQADCggIDgACAAAAAA==.',
Na='Nadíne:BAAANQAECgYIEAAAAA==.Nanukimon:BAAANQAECgEIAQAAAA==.Naughtgelic:BAAANQADCgQIAwAAAA==.',
Ne='Nedgamingttv:BAEANQAECgIIAwAAAA==.Nevaera:BAAANQADCgYIBgAAAA==.',
Ni='Ni:BAAANQAECgQIBAAAAA==.Nick:BAABNQAECoEiAAIRAAkJUSSAAwCjAwARAAkJUSSAAwCjAwAAAA==.Nikor:BAEANQADCggIGQAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQAECgEIAQAAAA==.Nomecoma:BAAANQAECgIIAwAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Noshom:BAAANQAECgMIBwAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ns='Nsyncrogue:BAAANQADCgQIBAAAAA==.',
Ny='Nymful:BAAANQAECgMIAwAAAA==.',
['Nè']='Nèlo:BAAANQAECgQIBAAAAA==.',
Ob='Obianstrider:BAAANQADCgYIDQAAAA==.',
Oc='Oceanspell:BAAANQAECgQIDgAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAAANQAECgYIDgAAAA==.',
On='Onlytoez:BAAANQADCggICgABNQAECggIGQANANYNAA==.',
Or='Orave:BAAANQADCggIGQAAAA==.Oromë:BAAANQABCgQIBAAAAA==.Orzik:BAAANQADCgcIBwAAAA==.',
Os='Ostena:BAAANQADCggIHAAAAA==.Osteole:BAAANQAECgMIBgABNQADCggIHAACAAAAAA==.',
Ou='Oulawdpriest:BAABNQAECoEdAAMOAAkJJRZMDAC1AgAOAAkJJRZMDAC1AgANAAEJYxOYiAA7AAAAAA==.',
Ov='Overture:BAAANQADCgQIBgAAAA==.',
Ow='Owthatburns:BAAANQADCgYIBgAAAA==.',
Pa='Pakszdude:BAAANQADCgUIBQAAAA==.Pandamonious:BAAANQADCggICAABNQAECgEIAgACAAAAAA==.Papawoof:BAAANQADCgQIBQABNQAECggIFgAIANMdAA==.Parkour:BAAANQADCgcIFAAAAA==.Paullyfists:BAAANQAECgQICgAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAgAAAA==.',
Po='Popkorn:BAACNQAFFIEHAAMSAAUJdB9oAAAvAQAQAAQJfxr3AgB4AQASAAMJViBoAAAvAQA1AAQKgR0AAxAACQmWJSQBAMsDABAACQl9JSQBAMsDABIAAgltIrsNANIAAAAA.Popkourne:BAAANQAECggICQABNQAFFAUIBwASAHQfAA==.Poplocks:BAAANQADCgYICgAAAA==.Porrana:BAAANQADCggIGQAAAA==.Powaqa:BAAANQAECgIIAgAAAA==.',
Pr='Praetorian:BAAANQAECgQIBgAAAA==.Praxxus:BAAANQADCgYIBgAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAAANQAECgYICwAAAA==.Quethelos:BAAANQADCgcIFwAAAA==.Quickbrew:BAAANQADCgQIBAAAAA==.Quickspell:BAAANQAECgYIDwAAAA==.',
Ra='Raalcar:BAAANQADCgUIBQAAAA==.Raedyyn:BAAANQAECgMIAwAAAA==.Ragarninn:BAAANQADCgcICwABNQAFFAEIAQACAAAAAA==.Ragendecay:BAAANQAECgMIAwAAAA==.Ragequits:BAACNQAFFIETAAITAAcJHCQ/AADpAgATAAcJHCQ/AADpAgA1AAQKgRwAAhMACQkOJu8DAMADABMACQkOJu8DAMADAAAA.Ragewar:BAAANQABCgcICQAAAA==.Rakshassa:BAAANQAECgMIBAAAAA==.Rawkphyst:BAAANQADCgQIAgAAAA==.Razrscale:BAAANQAECgEIAQAAAA==.',
Re='Redhuntsman:BAAANQADCgYIEQAAAA==.Regrow:BAAANQADCgcIBwABNQADCgcIEgACAAAAAA==.Reska:BAAANQADCgUICgAAAA==.',
Rh='Rholdentodor:BAAANQADCgEIAQABNQAECgQICwACAAAAAA==.',
Ri='Rindorin:BAAANQAECgEIAQAAAA==.Ritarepulsa:BAAANQADCgYIDAAAAA==.',
Ro='Rohra:BAAANQAECgQIBgAAAA==.Rozynwen:BAAANQADCgYICwAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQAECgEIAQAAAA==.Rukuna:BAAANQAECgEIAQAAAA==.Runecast:BAAANQAECgYICwAAAA==.',
Sa='Saelyrinth:BAAANQADCgUIBQABNQAECgIIAwACAAAAAA==.Salamence:BAAANQADCggICAABNQAECgMIBgACAAAAAQ==.Sambor:BAAANQAECggIBwAAAA==.Sarapheena:BAAANQAECgYIDgAAAA==.Sarouk:BAAANQAECgYICgAAAA==.Satansbride:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.Saterli:BAAANQAECgcIDgAAAA==.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAAANQAECgMIBQAAAA==.Sayygurl:BAAANQAECgEIAQAAAA==.',
Sc='Scalvert:BAAANQAECgQICwAAAA==.Scalypanda:BAAANQAECgYICgAAAA==.Scamander:BAAANQAECgcIDgABNQAECggIBgACAAAAAA==.Scoobs:BAAANQADCgQIBAABNQADCggIEAACAAAAAA==.Sculi:BAAANQAECgQIBwAAAA==.',
Se='Seiishiro:BAAANQADCggIFQAAAA==.Seldon:BAAANQAECgIIAgAAAA==.Senyor:BAAANQAECggIBAAAAA==.Seradormi:BAAANQADCgMIAwAAAA==.Seraphiel:BAAANQADCggIGgABNQADCgIIAgACAAAAAA==.',
Sh='Shadowpaksz:BAAANQAECgIIAwAAAA==.Shadowsneak:BAAANQAECgIIAgAAAA==.Shadowvixen:BAAANQAECgEIAQAAAA==.Shaelistra:BAAANQAECgIIAgAAAA==.Shalilama:BAAANQAFFAEIAQAAAA==.Shamboli:BAAANQADCggICQAAAA==.Shamirah:BAAANQADCgYIBgAAAA==.Shenderp:BAAANQAECgEIAQAAAA==.Shinerbock:BAAANQAECgUICgAAAA==.Shockitti:BAAANQAECgEIAQAAAA==.Shtark:BAAANQADCgcIDQAAAA==.',
Si='Silshara:BAAANQAECgcIEAAAAA==.Silverjustis:BAAANQAECgMIBAAAAA==.Siwe:BAAANQAECgQICAAAAA==.Six:BAAANQAECgIIAgABNQAECgMIAwACAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skribblez:BAAANQAECgUIEAAAAA==.Skyanna:BAAANQADCgYIDgAAAA==.',
Sl='Slackback:BAAANQAECggIBwABNQAECggIFgAUAPobAA==.Sloop:BAAANQADCgUIBQAAAA==.Sloot:BAAANQAECgcIBwAAAA==.',
Sn='Sneasel:BAAANQAECgMIBAABNQAECgQIBAACAAAAAA==.Snoogins:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.',
So='Sockszz:BAAANQAECgYIEQAAAA==.Songblade:BAAANQABCgUIBgAAAA==.Soulsy:BAABNQAECoEUAAILAAcJiyArIwCSAgALAAcJiyArIwCSAgAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAAANQAECgUIBQAAAA==.',
Sp='Splendorae:BAAANQAECgYIDAAAAA==.Sprints:BAAANQAECgQICQAAAA==.Spritz:BAAANQAECgUIDQAAAA==.Sprucewillis:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Spwany:BAAANQADCgIIAgAAAA==.Spyderelite:BAAANQAECgYIDAAAAA==.',
Sq='Squirrel:BAAANQAECgMIBwAAAA==.',
Ss='Ssuperss:BAAANQADCgQICQAAAA==.',
St='Stabbot:BAAANQAECgMIAwAAAA==.Starblood:BAAANQABCgMIAwAAAA==.Starspeaker:BAAANQADCgYIDAAAAA==.Stompmyballs:BAAANQAECgYIDQABNQAFFAcIEwATABwkAA==.Stoogotz:BAAANQADCgIIBAAAAA==.Studlebane:BAAANQABCgIIAgABNQAECgIIAwACAAAAAA==.Studlepalm:BAAANQAECgIIAwAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAAANQAECgYIDgAAAA==.Supersheep:BAAANQAECgMIAwAAAA==.Suvien:BAAANQADCgUIBQAAAA==.',
Sy='Sylvarian:BAAANQAECgIIAgAAAA==.Sylvinna:BAAANQADCgcIDgAAAA==.',
Ta='Tagda:BAAANQADCggICAAAAA==.Taterdotz:BAAANQAECgIIAgAAAA==.Tatortwats:BAAANQAFFAEIAgAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tengrit:BAAANQADCgIIAgAAAA==.Tephine:BAAANQAECgYIDQAAAA==.Tepicoyotl:BAAANQAECgcIDwAAAA==.',
Th='Thaymor:BAAANQADCgMIAwAAAA==.Thebigkitti:BAAANQADCgEIAQAAAA==.Thelonecone:BAABNQAECoEaAAIVAAkJqCIuAwBuAwAVAAkJqCIuAwBuAwAAAA==.Theodor:BAAANQAECgEIAQAAAA==.Theoganth:BAAANQAECgEIAQAAAA==.Theraphee:BAAANQADCgYIEAAAAA==.Therym:BAAANQADCgEIAQABNQAECgcIDwACAAAAAA==.Thomwizard:BAAANQADCggIFAAAAA==.Thormorn:BAAANQADCggIEQAAAA==.Thunnha:BAAANQADCgYIEwAAAA==.',
Ti='Tierali:BAAANQADCgYICgAAAA==.Tio:BAAANQADCggIEwAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAAANQAECgIIAgABNQAECgMIAwACAAAAAA==.Torrinchaos:BAAANQADCgQIBAAAAA==.Tosala:BAAANQAECgIIAgAAAA==.Totemkiller:BAAANQAECgIIAwAAAA==.',
Tr='Traael:BAAANQAECgEIAQAAAA==.Treesap:BAAANQAECgYIDAAAAA==.Trinityeve:BAAANQAECgEIAQAAAA==.Trmz:BAAANQAECgYICgAAAA==.Trnzlock:BAAANQAECgUICQABNQAECgYICgACAAAAAA==.',
Tu='Tulanii:BAAANQADCgIIAgAAAA==.Tumble:BAAANQAECgEIAQAAAA==.',
Tw='Twignberryz:BAAANQADCgYIBgAAAA==.Twinkie:BAAANQAECgUIBgAAAA==.Twodogz:BAAANQAECgIIBAAAAA==.',
Ty='Tyious:BAAANQAECgYIDgAAAA==.Tyndara:BAAANQAECgIIAgAAAA==.',
Ub='Ubavoke:BAAANQADCgcIDQAAAA==.',
Uk='Ukita:BAAANQAFFAEIAQAAAA==.',
Ur='Ursane:BAAANQAECgYIDgAAAA==.Ursully:BAAANQAECgIIAgAAAA==.',
Uz='Uzi:BAAANQAECgQIBQAAAA==.',
Va='Valentíne:BAAANQADCgYIDAAAAA==.Valhalla:BAAANQAECgIIAgAAAA==.Vannaran:BAAANQABCgIIAgAAAA==.Vanncint:BAAANQAECgIIAgAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Vexus:BAABNQAECoEWAAIUAAgJ+htlGQCqAgAUAAgJ+htlGQCqAgAAAA==.',
Vi='Vixly:BAAANQADCgUICgAAAA==.',
Vl='Vladios:BAAANQAECgQIBQAAAA==.',
Vo='Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Walolas:BAAANQADCggIFQAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgcIEAAAAA==.Watchmeburst:BAAANQADCgYICAAAAA==.',
Wh='Whaler:BAAANQAECggIBAAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQAECgQIBAACAAAAAA==.Windowskey:BAAANQAECgYIAwABNQAECggICgACAAAAAA==.',
Wu='Wuzntmyfault:BAAANQADCgcIEgAAAA==.',
Wy='Wyldfyire:BAAANQAECgIIAwAAAA==.',
Xa='Xaven:BAAANQAECgMIAwAAAA==.Xavenuke:BAAANQADCgcIDQABNQAECgMIAwACAAAAAA==.',
Xi='Xiaotao:BAAANQAECgMIAwAAAA==.',
Xt='Xtraxtra:BAAANQADCggICQABNQAECgUIDAACAAAAAA==.',
Yo='Yoga:BAAANQADCggIFgAAAA==.',
Za='Zabra:BAAANQADCgcIFAAAAA==.Zahshia:BAAANQADCggIGQAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAAANQAFFAIIAgAAAA==.Zaylian:BAAANQAECgcIEAAAAA==.Zayragossa:BAAANQAECgcIEAAAAA==.Zayrah:BAAANQADCggIGQABNQAECgcIEAACAAAAAA==.',
Ze='Zeerkk:BAAANQAECgQICAAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.',
Zi='Zirilian:BAAANQADCgQICAABNQAECgIIAwACAAAAAA==.',
Zo='Zoomzoom:BAAANQAECgUIBgABNQAECgkJHQAOACUWAA==.',
Zu='Zulkraa:BAAANQADCggIEQAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Ài']='Àirén:BAAANQAECgUIBgAAAA==.',
['Åb']='Åbon:BAAANQADCgcIEAAAAA==.',
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
