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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Priest-Shadow','DemonHunter-Vengeance','Priest-Holy','Rogue-Outlaw','Hunter-BeastMastery','Druid-Balance','Mage-Arcane','Druid-Restoration','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Paladin-Holy','Shaman-Restoration','Monk-Brewmaster','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Unholy','DeathKnight-Blood',}
local provider = {region='US',realm='Stormreaver',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaragondelta:BAAANQADCgYIBgABNQAFFAYIBwABAF8QAA==.Aaragonius:BAAANQADCgYICAABNQAFFAYIBwABAF8QAA==.Aaragonneo:BAABNQAFFIEHAAIBAAYJXxAeAAAlAgABAAYJXxAeAAAlAgAAAA==.',
Ab='Ablé:BAAANQAECgQIBAAAAA==.',
Ac='Ackreseth:BAAANQADCggIDQAAAA==.',
Ad='Adriön:BAAANQADCgYIBgAAAA==.',
Ae='Aeko:BAAANQADCgcICgAAAA==.Aemeath:BAAANQADCgIIAgAAAA==.Aergoss:BAAANQAECgIIAgAAAA==.Aeristeia:BAAANQAECgIIAgAAAA==.',
Ah='Ahriena:BAAANQADCgEIAQABNQAFFAMIBAACAAAAAA==.',
Ai='Aiee:BAAANQADCgUIBQAAAA==.Aizén:BAAANQAECgIIAgAAAA==.',
Al='Allaboutme:BAAANQADCgUIBgAAAA==.',
Am='Amad:BAAANQADCgUIBQAAAA==.Amourn:BAAANQADCgUIBQAAAA==.',
An='Analrek:BAAANQADCggIDgAAAA==.Antoinedruid:BAAANQAECgcIDQABNQAFFAUIBgADAHgPAA==.',
Ap='Apocalypsis:BAAANQADCgYIBgAAAA==.Apodal:BAAANQAECgcIDQABNQAFFAYIBwAEAKoQAA==.Apoluss:BAAANQADCgYICwAAAA==.',
Ar='Arock:BAAANQAECgMIAwAAAA==.Arrithion:BAAANQAECgEIAQAAAA==.Arthaz:BAABNQAFFIEGAAIDAAUJeA8lAADaAQADAAUJeA8lAADaAQAAAA==.',
As='Astandra:BAAANQADCgMIAwAAAA==.',
At='Atexnogaraa:BAAANQAECgcIDQABNQAFFAYIBwABAF8QAA==.',
Av='Averelles:BAAANQAECgEIAQAAAA==.',
Aw='Awwik:BAAANQADCgYIDAAAAA==.',
Az='Azsharaa:BAAANQAECgMIAwAAAA==.',
Ba='Badaboomkin:BAAANQADCgcICwABNQAECgYIBQACAAAAAA==.Baeldun:BAAANQADCggIDAAAAA==.Baethoven:BAAANQADCggIDgAAAA==.Bagagwa:BAAANQADCggIDgAAAA==.Ballzout:BAAANQAECgYIBQAAAA==.Bamix:BAAANQADCgYIBgAAAA==.Bashm:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.',
Be='Beelzemoan:BAAANQADCgIIAgAAAA==.Beens:BAAANQAFFAEIAQAAAA==.Beewitched:BAAANQADCgQIBQAAAA==.Beloved:BAAANQAECgEIAQAAAA==.Belowzerolol:BAAANQAECgcIDQABNQAFFAYIBwAFABofAA==.',
Bi='Bigchimpin:BAAANQADCgcIBwAAAA==.',
Bl='Bloodlust:BAAANQAECgUIBwAAAA==.',
Bo='Boomboompow:BAAANQADCgUIBQAAAA==.',
Br='Breadbowl:BAAANQADCgcIBwAAAA==.Brrzerk:BAAANQADCgcIBwAAAA==.',
Bu='Bubblesburst:BAAANQADCgMIAwABNQADCgQIBQACAAAAAA==.Bubblëdin:BAAANQADCgYICgAAAA==.Buckee:BAAANQAECgEIAQAAAA==.Buffoutlaw:BAAANQAECgcIDQABNQAFFAYIBwAGANIlAA==.Bullzzeye:BAAANQAECgcIDQAAAA==.Butternipz:BAAANQADCgcIBwAAAA==.',
By='Byshop:BAAANQAECgMIAwAAAA==.',
Ca='Cabe:BAAANQADCggIDgAAAA==.Caerra:BAAANQADCgIIAgAAAA==.Caggarm:BAAANQADCgYICQAAAA==.Cailber:BAAANQADCgUIBwAAAA==.Callipriest:BAAANQAECgIIAgAAAA==.Castermaster:BAAANQAECgQIBQAAAA==.',
Ce='Celthrinor:BAAANQADCgYIBgAAAA==.',
Ch='Chaeni:BAAANQADCgIIAgAAAA==.Chakkah:BAAANQADCgQIBAAAAA==.Cheekies:BAAANQAECgEIAQABNQAECgYICQACAAAAAA==.Chillyy:BAAANQAECgUIBgAAAA==.Chispot:BAAANQAECgEIAQAAAA==.Chitorpedo:BAAANQAECgQIBAAAAA==.',
Ci='Cidel:BAAANQADCgMIAwAAAA==.Cifer:BAAANQADCgYIBgAAAA==.',
Co='Comatoast:BAAANQAECgMIBAAAAA==.',
Cr='Crackalaks:BAAANQADCgYIBgAAAA==.Crazyb:BAAANQADCggICgAAAA==.Croith:BAAANQAECgIIAgAAAA==.Crotch:BAAANQABCgEIAgAAAA==.Cryingorc:BAAANQADCgYICQAAAA==.Crúz:BAAANQADCgQIBAAAAA==.',
Cw='Cwap:BAAANQADCggIDwAAAA==.',
Cy='Cyndraylitha:BAAANQADCgYIBgAAAA==.',
Da='Daddywaumpus:BAAANQADCggICAAAAA==.Danas:BAAANQADCgYICwAAAA==.Davicurn:BAAANQADCgcIBwAAAA==.Daythyme:BAAANQADCgYICQAAAA==.',
De='Deadornot:BAAANQADCggIDAAAAA==.Deadywaumpus:BAAANQAECgQIBgAAAA==.Deathbubbles:BAAANQADCgYIBwAAAA==.Deathkong:BAAANQAECgcIDAAAAA==.Deathofdager:BAAANQADCggICAAAAA==.Deetwenty:BAAANQADCgUIBQAAAA==.Deeztotemz:BAAANQADCgQIBAAAAA==.Desiiria:BAAANQADCgUIBQAAAA==.Deylicious:BAAANQADCgYIBgABNQAFFAYIBwAHAKcYAA==.',
Dh='Dhani:BAAANQADCggIDgAAAA==.',
Di='Dietdrpibb:BAAANQADCgcIDQAAAA==.Diiemoar:BAAANQADCggIDgAAAA==.Dijoe:BAAANQAECgMIAwAAAA==.Dippndotz:BAAANQAECggIDgAAAA==.Discfunction:BAAANQADCgcIDAAAAA==.',
Do='Doafliploser:BAAANQADCgYIBgAAAA==.Dogwalterll:BAAANQAECgMIAwAAAA==.Dohvahkiin:BAAANQADCgYIBgAAAA==.',
Dr='Draaragon:BAAANQADCgMIAwABNQAFFAYIBwABAF8QAA==.Dragonboffa:BAAANQADCgYIDAAAAA==.Dragonlyfans:BAAANQAECgcIDQABNQAFFAYIBwAIAJ0aAA==.Dripz:BAAANQADCggIDgAAAA==.Drive:BAAANQADCggIDgAAAA==.Dryadwood:BAAANQADCgYIBgAAAA==.',
Du='Dubby:BAAANQAECgQIBAAAAA==.Dumptruckdan:BAAANQAECgcIDQABNQAFFAYIBwAJACARAA==.',
Dw='Dwagon:BAAANQADCgcICAABNQAFFAUIBgAKAKsPAA==.',
Ea='Eardi:BAAANQAECgYIBwAAAA==.Earthpounder:BAAANQADCggIDgAAAA==.',
Ec='Echoez:BAAANQAECgQIBQABNQADCgYIEAACAAAAAA==.',
Ee='Eebo:BAAANQADCgMIAwAAAA==.',
El='Elbram:BAAANQADCggICAAAAA==.',
Em='Emilil:BAAANQADCgMIAwAAAA==.Eminence:BAAANQADCggIDgAAAA==.',
Er='Erdorco:BAAANQADCggICwABNQAECgEIAQACAAAAAA==.',
Es='Escanor:BAAANQADCgYICQAAAA==.Esu:BAAANQADCgIIAQAAAA==.',
Eu='Eudaimonia:BAAANQADCgUICQAAAA==.',
Ex='Exias:BAAANQADCggIDAAAAA==.',
Fa='Facebeata:BAAANQAECgQIBQAAAA==.Faize:BAAANQADCggIDgABNQAFFAEIAQACAAAAAA==.Falae:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.Fathêrhêlp:BAAANQADCgEIAQAAAA==.Faunuis:BAABNQAFFIEHAAMIAAYJnRpWAACrAQAIAAQJ9B1WAACrAQAKAAIJBw2yAACfAAAAAA==.Fawnbby:BAAANQADCgUICAAAAA==.',
Fe='Featherbrain:BAAANQADCggIDQAAAA==.Felhell:BAAANQADCggICAABNQAECgUIBgACAAAAAA==.Ferenyet:BAAANQADCgYIBgAAAA==.Fermagus:BAAANQAECgQIBgAAAA==.',
Fi='Fistflurry:BAAANQADCgUIBQAAAA==.Fistlad:BAABNQAFFIEHAAILAAYJER4DAACcAgALAAYJER4DAACcAgAAAA==.Fizzybubbles:BAAANQAECgEIAQAAAA==.',
Fl='Flamehunter:BAAANQAECgQIBQAAAA==.Flapple:BAAANQAECggIDgAAAA==.Flu:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Flûffy:BAAANQADCgYICwAAAA==.',
Fr='Freaknikk:BAAANQAECgUIBgABNQAECgYIDAACAAAAAA==.Freightraìn:BAAANQADCgIIAgABNQAECgQIBgACAAAAAQ==.Frozalth:BAAANQADCgUIBgAAAA==.',
Fu='Fudgemuffin:BAAANQADCgcIDQAAAA==.',
['Fë']='Fënrïr:BAAANQAECgEIAQAAAA==.',
['Fú']='Fúzzybútt:BAAANQADCgMIAwAAAA==.',
Ga='Garlim:BAAANQADCgUIBQAAAA==.Gazebogary:BAAANQADCgQIBAABNQAFFAYIBwAJACARAA==.',
Ge='Gellysong:BAAANQABCgQIBgAAAA==.Gerlim:BAAANQADCgEIAQAAAA==.',
Gi='Gix:BAAANQADCgQIBQAAAA==.',
Gl='Glopanx:BAAANQADCgYIDAAAAA==.',
Go='Goresnot:BAAANQADCgUICwAAAA==.',
Gr='Granrok:BAAANQADCgYIBgAAAA==.Gravedarknes:BAAANQAECgUIBgAAAA==.Greendog:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Grishknight:BAAANQADCgIIAgAAAA==.',
Gu='Guap:BAAANQAECgcIDQABNQAFFAYIBwALABEeAA==.Gunray:BAAANQADCgUIBQAAAA==.Guttamane:BAAANQADCgUIBQAAAA==.Gutx:BAAANQADCgYICwAAAA==.',
Gy='Gyarrados:BAAANQADCgQIBAAAAA==.Gypsywolfe:BAAANQADCggIDgAAAA==.',
['Gí']='Gífted:BAAANQAECgQIBgAAAA==.',
Ha='Haleybeary:BAAANQADCgcIDAAAAA==.Harawing:BAAANQADCgUIBQAAAA==.Hargrim:BAAANQADCggICAAAAA==.Hastega:BAAANQAECgQIBAAAAA==.Haydonk:BAAANQABCgEIAQAAAA==.',
He='Herbage:BAAANQADCggIDgAAAA==.Herrbjorn:BAAANQADCgYIBgAAAA==.',
Hi='Hinata:BAAANQADCgQIBAAAAA==.Hippopotamus:BAAANQADCggIDgAAAA==.Hitaman:BAAANQADCggIDgAAAA==.',
Ho='Holybaguette:BAAANQADCggIDAAAAA==.Holycritbro:BAAANQADCgcIDQAAAA==.Horôn:BAAANQADCgYIBgAAAA==.Houndoomm:BAAANQADCggIDgAAAA==.',
Hr='Hriste:BAAANQADCgYICwAAAA==.',
Hu='Hunteress:BAAANQADCgQIBAAAAA==.Huntyhunt:BAAANQADCggIDAAAAA==.',
Im='Impmafia:BAAANQABCgIIBAAAAA==.',
In='Incognetus:BAAANQAECgQIBgAAAQ==.Insurrection:BAAANQADCgYICAABNQAECgMIBAACAAAAAA==.',
Ja='Jaduen:BAAANQADCggIDwAAAA==.Jaesedar:BAAANQAFFAEIAQAAAA==.Jaycen:BAAANQADCgQIBAABNQAECgQIBgACAAAAAQ==.',
Je='Jellythug:BAAANQADCgUIBQAAAA==.Jenny:BAAANQADCgUIBgAAAA==.Jerksnknight:BAAANQADCggIDgAAAA==.Jethon:BAAANQADCgcICwAAAA==.Jexro:BAAANQAECgcIDQAAAA==.Jezebaal:BAAANQADCgUIBAAAAA==.',
Jg='Jgremlin:BAAANQADCgUIBAAAAA==.',
Jo='Johnseenah:BAAANQADCgYIDAAAAA==.Jonnybravo:BAAANQAECgEIAQAAAA==.',
Jr='Jrrd:BAAANQAECgIIAgAAAA==.',
Ju='Judgmentoe:BAAANQADCgYIBgAAAA==.Jusstice:BAAANQADCggIDgAAAA==.',
Ka='Kack:BAAANQADCgYICgAAAA==.Kalvosa:BAAANQADCgEIAQAAAA==.Karlbarx:BAAANQADCgQIBAAAAA==.Kasaa:BAAANQAECgIIAgAAAA==.Kasheira:BAAANQADCggIDgAAAA==.Katti:BAAANQAECgQIBAAAAA==.Katzfiel:BAAANQADCggIDgAAAA==.Kaytwo:BAAANQAFFAEIAgAAAA==.',
Kb='Kblasti:BAAANQADCggIDgABNQAECgQIBgACAAAAAA==.Kblastissimo:BAAANQAECgQIBgAAAA==.',
Ke='Kersplode:BAAANQADCgUIBQABNQAECgQIBgACAAAAAA==.',
Kh='Khariia:BAAANQADCgQIBAAAAA==.',
Ki='Kieloran:BAAANQADCgUIBQAAAA==.Kieralyn:BAAANQADCggIDgAAAA==.Kiltlifter:BAAANQADCgcICgAAAA==.',
Ko='Koaladashian:BAAANQAECggIDwAAAA==.Koalaficent:BAAANQAECggIDgAAAA==.Kojodruid:BAAANQADCgYICgAAAA==.Kong:BAAANQADCggIDQAAAA==.Kookta:BAAANQAECgQIBgAAAA==.Kozmo:BAAANQADCgYICgAAAA==.',
Kr='Kreep:BAAANQADCgUIBQAAAA==.Kresnik:BAAANQADCgUIBQAAAA==.',
Ku='Kundin:BAAANQADCggICAABNQAECggIDwACAAAAAA==.Kurai:BAAANQAECgIIAgAAAA==.Kutaki:BAAANQADCgcIDAAAAA==.',
['Kí']='Kíngbradley:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.',
La='Lasrin:BAAANQAECgcICwAAAA==.Lavenia:BAAANQADCggIDAAAAA==.',
Ld='Ldawg:BAAANQAECgIIAgAAAA==.',
Le='Leastzenmonk:BAAANQAECgYICgABNQAECggIDgACAAAAAA==.',
Li='Liello:BAAANQADCggICQAAAA==.Lightchaos:BAAANQADCggICQAAAA==.Lightice:BAAANQADCgMIAwAAAA==.Lilgaypunk:BAAANQAECgcIEAAAAA==.Littlecyka:BAAANQADCggICAAAAA==.',
Lo='Locoscar:BAAANQAECggIDgAAAA==.Loktark:BAABNQAFFIEHAAIGAAYJ0iUBAACKAgAGAAYJ0iUBAACKAgAAAA==.Lotei:BAAANQADCgYICgAAAA==.',
Lu='Luckylock:BAAANQADCgYIBgAAAA==.Lula:BAAANQADCgIIAgAAAA==.Lunasolz:BAEANQADCggICAAAAA==.Lustíé:BAAANQADCgcIDQAAAA==.',
['Là']='Lànthus:BAAANQAECgMIAwAAAA==.',
Ma='Magev:BAAANQADCggIDgAAAA==.Magiccheif:BAAANQAECgQIBAAAAA==.Magnuz:BAAANQADCgQIBwAAAA==.Maisharona:BAAANQADCgYIDAABNQAECgQICAACAAAAAA==.Manginah:BAAANQADCggIDQABNQAECgYIBQACAAAAAA==.Mauringo:BAAANQADCggIAwAAAA==.Mavanthis:BAAANQADCgYICwAAAA==.Maxdizaster:BAAANQADCggIDgAAAA==.Mazkaz:BAAANQADCgUIBQAAAA==.',
Mc='Mcbonk:BAABNQAECoERAAMMAAkJrhuPCQD/AgAMAAkJyRiPCQD/AgANAAIJlyKyBgDKAAAAAA==.Mckniferson:BAAANQADCgIIAwAAAA==.',
Me='Messybedhead:BAAANQAECgYICAABNQADCgYIBgACAAAAAA==.Methindour:BAAANQADCgcIDAAAAA==.',
Mi='Mintwiskers:BAAANQADCggIDgAAAA==.Misiana:BAAANQAECgQIBgAAAA==.Mivix:BAAANQAECgUICAABNQAFFAUIBgAFAIgPAA==.',
Mo='Mom:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Monkeyclaw:BAAANQAECgMIBAAAAA==.Moonfist:BAAANQADCgQIBAAAAA==.Mordrak:BAAANQAECgIIAgAAAA==.Mordë:BAAANQAECgIIBQAAAA==.Mormzie:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Morwy:BAAANQADCgUICgAAAA==.Moøbytoo:BAAANQAECgMIAwABNQAECgQIBAACAAAAAA==.',
Ms='Msedd:BAAANQADCgMIAwAAAA==.',
Mu='Mugged:BAAANQAECgQIBgAAAA==.Muinogaraa:BAAANQADCggIEAABNQAFFAYIBwABAF8QAA==.Mum:BAAANQAECgQIBgAAAA==.Mushmouth:BAAANQAECgQIBAAAAA==.',
My='Mysiara:BAAANQADCgYICwAAAA==.',
['Mì']='Mìchael:BAAANQADCggIEAAAAA==.',
['Mú']='Músu:BAAANQADCgYIBgAAAA==.',
Na='Nampur:BAAANQAECgEIAQAAAA==.Naril:BAAANQADCggIDgAAAA==.Narvana:BAAANQAECgEIAQAAAA==.Naughtyboy:BAAANQAECgEIAQABNQAECggIDAACAAAAAA==.Nayalla:BAAANQADCgcICwAAAA==.',
Ni='Nityblast:BAAANQADCgUIBQAAAA==.',
No='Nodrus:BAAANQADCgUIBQAAAA==.Nogaraa:BAAANQADCggIEAABNQAFFAYIBwABAF8QAA==.Novath:BAABNQAFFIEHAAIOAAYJLx0KAABdAgAOAAYJLx0KAABdAgAAAA==.',
Ny='Nyssarissa:BAAANQAECgQIBQAAAA==.',
['Nè']='Nèliel:BAAANQAECgIIAgAAAA==.',
Oa='Oakenstream:BAAANQADCgIIAgAAAA==.',
Ou='Oui:BAAANQADCgYIBgAAAA==.',
Ov='Overheated:BAAANQADCgYIBwAAAA==.',
Pa='Paalaz:BAAANQAECgcICgAAAA==.Paeldryth:BAAANQAECggIEAAAAA==.Paliesto:BAAANQADCgQIBAAAAA==.Paljin:BAAANQADCgIIAQAAAA==.Palmface:BAAANQADCggIDgAAAA==.Panatepriest:BAAANQADCgYICQAAAA==.Pandadante:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Pandatunado:BAAANQAECgQICAAAAA==.Panky:BAAANQADCggIDgAAAA==.',
Pe='Pedrocerrano:BAAANQADCgUIBwAAAA==.Pelt:BAAANQAECgQIBgAAAA==.Pewbot:BAAANQADCgYICgABNQAECgQIBgACAAAAAQ==.',
Ph='Phoebë:BAAANQADCgEIAgAAAA==.Phusiion:BAAANQADCgEIAQAAAA==.',
Pi='Pickledin:BAAANQAECgEIAQAAAA==.',
Pk='Pkmntrainer:BAAANQADCgYICwABNQADCgcIDQACAAAAAA==.',
Pl='Please:BAABNQAFFIEHAAIPAAYJgAYqAADhAQAPAAYJgAYqAADhAQAAAA==.Pleasetwo:BAAANQAECgcIDQABNQAFFAYIBwAPAIAGAA==.Plumaril:BAAANQADCgcICgAAAA==.',
Pp='Ppleakin:BAAANQAECgQIBAAAAA==.',
Pr='Pranzar:BAAANQAECgMIAQAAAA==.Prepdagoat:BAAANQADCgYICwABNQADCgQIBAACAAAAAA==.',
Pu='Pullo:BAAANQAECgQICAAAAA==.Punctualpaul:BAAANQAECgMIAwABNQAFFAYIBwAOAC8dAA==.Purple:BAAANQAECgMIAwAAAA==.',
Py='Pyrê:BAAANQADCgQIBAAAAA==.',
Qu='Quidditch:BAAANQAECgQIBAAAAA==.',
Qw='Qwadsfwfgads:BAABNQAFFIEGAAIKAAUJqw8TAAC5AQAKAAUJqw8TAAC5AQAAAA==.Qwamsfwfgads:BAAANQAECgIIAgABNQAFFAUIBgAKAKsPAA==.',
Ra='Rabbi:BAAANQADCgIIBAABNQAECgQIBgACAAAAAQ==.Raelavent:BAAANQAECgEIAQAAAA==.Ragrappy:BAABNQAFFIEHAAIFAAYJGh8FAABpAgAFAAYJGh8FAABpAgAAAA==.Raiju:BAAANQADCgcICwAAAA==.Ramped:BAAANQADCgUIBQAAAA==.Raszahk:BAAANQAECgUIBQABNQAECgcICAACAAAAAA==.',
Re='Reavêr:BAAANQADCggICwAAAA==.Redreximus:BAAANQAECgQIBAAAAA==.Regilock:BAAANQADCgcICgABNQAECgIIBAACAAAAAA==.Retlec:BAAANQADCgUIBQAAAA==.',
Ri='Rickaz:BAAANQADCgUIBAAAAA==.Ripto:BAAANQAECgEIAQAAAA==.',
Ro='Roshana:BAAANQADCggIDgAAAA==.Rothoof:BAAANQAECgMIAwAAAA==.',
Ru='Rudnos:BAAANQADCgMIAgABNQAECgIIAwACAAAAAA==.',
Ry='Ryptup:BAAANQADCggICAAAAA==.',
['Rô']='Rôinujj:BAAANQADCgIIAwAAAA==.',
Sa='Safiyah:BAAANQAECgIIAgAAAA==.Saltyevoker:BAAANQADCgYIBwAAAA==.Same:BAAANQAECgcIDQABNQAFFAYIBwAOAC8dAA==.Sandorstus:BAAANQAECgEIAgAAAA==.Saothome:BAAANQADCgUICQAAAA==.Saywho:BAAANQADCgUICQAAAA==.',
Sc='Scienta:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.Scope:BAAANQADCgYIBgAAAA==.Scrubdk:BAAANQADCgcIBwAAAA==.Scúbasteve:BAAANQADCgcIDQAAAA==.',
Se='Sefirot:BAAANQADCgcIDAAAAA==.Selinddra:BAAANQADCgcICgAAAA==.',
Sh='Shadebringer:BAAANQADCgcIDAAAAA==.Shamdaddy:BAAANQADCgIIAgAAAA==.Shamezee:BAAANQAECgEIAgAAAA==.Shampoo:BAAANQADCgcIBwAAAA==.Sharlotte:BAAANQADCgQIBAAAAA==.Shilas:BAAANQAECgcIDQABNQAECggIEAACAAAAAA==.Shishkabug:BAAANQADCgIIAgAAAA==.',
Si='Sicilianhero:BAAANQADCggIDAAAAA==.Sinsyn:BAAANQADCggICAAAAA==.Sinwarrior:BAAANQADCggIEAABNQAECgkJGgAQAIIdAA==.Sizz:BAAANQADCgQIBAAAAA==.',
Sk='Skipcawk:BAABNQAFFIEHAAMHAAYJpxgWAAAwAQAHAAMJph0WAAAwAQARAAMJqBNgAQAMAQAAAA==.Skorpco:BAAANQAECgcIDQAAAA==.',
Sl='Sluggo:BAAANQADCggICAAAAA==.',
Sm='Smulol:BAAANQAECgIIAgAAAA==.',
Sn='Snoopfrogg:BAAANQAECgQIBAAAAA==.',
So='Solfire:BAAANQADCgYICwAAAA==.Soltero:BAEANQADCgUIBwABNQADCggICAACAAAAAA==.Somehobo:BAAANQADCgQIBgAAAA==.Sometingwong:BAAANQADCgQIBAAAAA==.',
Sp='Spamheal:BAAANQADCgcIDQAAAA==.Sparkle:BAAANQADCgIIAQAAAA==.Spliffy:BAAANQABCgEIAQAAAA==.',
St='Stabber:BAAANQADCgQIBAAAAA==.Stoc:BAAANQAECgMIAwAAAA==.Stormweaver:BAAANQADCgcICwAAAA==.',
Su='Suinogaraa:BAAANQADCgYIBgABNQAFFAYIBwABAF8QAA==.Sunderwhere:BAAANQAECgcICAAAAA==.',
Sw='Swann:BAAANQAECgIIAwAAAA==.Swavor:BAAANQADCggIDgAAAA==.Sweetbella:BAAANQADCgMIAwAAAA==.Swurves:BAAANQADCggIDgAAAA==.',
Sy='Symbio:BAAANQADCggIDQAAAA==.Syna:BAAANQADCgcIDQAAAA==.',
Ta='Taearo:BAAANQADCggIDgAAAA==.Taime:BAAANQAECgEIAQAAAA==.Talirn:BAAANQADCggIDgAAAA==.Tallanvor:BAAANQADCgYIBgAAAA==.',
Te='Teddywaumpus:BAAANQADCgYIBgAAAA==.Tendecay:BAAANQADCggIDgAAAA==.',
Th='Thanquiol:BAABNQAFFIEHAAIEAAYJqhAEAAAPAgAEAAYJqhAEAAAPAgAAAA==.Thebaraj:BAAANQAECgMIBAAAAA==.Thebigdawg:BAAANQADCgUICAAAAA==.Thedruidd:BAAANQADCgYIBQAAAA==.Theeassassin:BAAANQADCgIIAQAAAA==.Thelance:BAAANQADCgYICQAAAA==.Thrilled:BAAANQADCgcIDQAAAA==.Thyora:BAAANQAECggIDwAAAA==.',
Ti='Tijdruid:BAAANQADCgYICQAAAA==.',
To='Tommypickles:BAABNQAFFIEHAAIJAAYJIBEpAAA4AgAJAAYJIBEpAAA4AgAAAA==.Tomtrocity:BAAANQADCgMIBAAAAA==.Tonestar:BAAANQADCgUIBQAAAA==.Toturaka:BAAANQADCgUIBQAAAA==.',
Tr='Trackerjoe:BAAANQADCgMIBAAAAA==.Train:BAAANQADCgIIAgABNQAECgQIBgACAAAAAQ==.Treerex:BAAANQADCggICAAAAA==.Troljin:BAAANQAECgIIAgAAAA==.Trollpaladin:BAAANQADCgcIDQAAAA==.',
Ts='Tsipayeoc:BAAANQADCgEIAQAAAA==.',
Tw='Twk:BAAANQADCgYIBgAAAA==.',
Ty='Tyrgann:BAAANQADCgUIBQAAAA==.Tytoflamina:BAAANQAECgEIAQAAAA==.',
Um='Umalinn:BAAANQADCggIDgAAAA==.',
Va='Vacca:BAAANQADCggICAAAAA==.Vahvadon:BAAANQADCgQIBAAAAA==.Valucia:BAAANQADCgEIAQAAAA==.Vandagar:BAAANQAECgMIAwAAAA==.Vapor:BAAANQAECgYIEwAAAA==.Varsity:BAAANQAECggIEAAAAA==.Vason:BAAANQADCgMIAwAAAA==.',
Ve='Ventumceleri:BAAANQADCgUIBQAAAA==.',
Vi='Vinyasa:BAAANQADCggIDgAAAA==.',
Vo='Voodoobeast:BAAANQADCggICAAAAA==.',
Wa='Waremtae:BAAANQADCgEIAQAAAA==.',
Wh='Whyp:BAAANQAECgcIDAAAAA==.',
Wi='Wickle:BAAANQADCgcIBwAAAA==.Wingdaz:BAEANQADCggICQABNQAECgYICgACAAAAAA==.',
Xi='Xidara:BAAANQADCgEIAQAAAA==.Xivei:BAABNQAFFIEGAAIFAAUJiA9YAAC9AQAFAAUJiA9YAAC9AQAAAA==.',
Xl='Xlegolas:BAAANQADCgIIAQAAAA==.',
Xo='Xorac:BAAANQADCgcICwAAAA==.',
Xz='Xzach:BAAANQAECgcIDQAAAA==.',
Yi='Yinlou:BAAANQADCgYICgAAAA==.',
Yo='Yorha:BAAANQADCgEIAQABNQAFFAEIAQACAAAAAA==.',
Ys='Yshtolà:BAEANQADCgYICAABNQADCggICAACAAAAAA==.',
['Yì']='Yìffist:BAAANQADCgYIDAAAAA==.',
Za='Zachx:BAABNQAFFIEHAAQSAAYJrBgXAAA+AQASAAMJESMXAAA+AQATAAMJ+BFTAAAzAQAUAAEJuhddAABfAAAAAA==.Zaegorn:BAAANQADCgQIBAAAAA==.Zargar:BAAANQAECgcIDQAAAA==.Zarmakai:BAABNQAFFIEGAAMVAAUJ2RUZAACNAQAVAAQJXxgZAACNAQAWAAEJxAs2BQAzAAAAAA==.',
Zi='Zivie:BAAANQAECgEIAQAAAA==.',
Zu='Zurry:BAAANQABCgEIAQAAAA==.',
Zy='Zygon:BAAANQAECgQIBwAAAA==.',
['Ök']='Ökko:BAAANQADCggIDwAAAA==.',
['Öw']='Öwly:BAAANQAECgMIAwAAAA==.',
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
