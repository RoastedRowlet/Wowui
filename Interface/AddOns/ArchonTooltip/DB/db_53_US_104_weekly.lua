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

local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Priest-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Arms',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acuminada:BAAANQADCgIIAgAAAA==.Acuna:BAAANQAECgMIBAAAAA==.',
Ad='Adison:BAAANQADCgYIBgAAAA==.',
Af='Affliction:BAAANQAECgIIAgAAAA==.',
Ai='Airz:BAAANQAECgIIAgAAAA==.',
Ak='Akâkiôs:BAAANQAECgEIAQAAAA==.',
Al='Aladorman:BAAANQADCgYIDAAAAA==.Alamo:BAAANQADCggIDwAAAA==.Albertlin:BAAANQAECgIIAgAAAA==.Alexinar:BAAANQADCgcICgAAAA==.',
Am='Amakuagsak:BAAANQADCggIEwAAAA==.Amicus:BAAANQADCggIFAAAAA==.Ampmage:BAAANQAECgEIAQAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.',
Ap='Apollo:BAAANQAECgMIBAAAAA==.Apolynnæ:BAAANQAECgYICgAAAA==.',
Ar='Araniss:BAAANQADCggIFAAAAA==.Arasthel:BAAANQADCgcIDAAAAA==.Aratrath:BAAANQAECgQIBwAAAA==.Aryasilly:BAAANQAECgMIAwAAAA==.',
As='Asdi:BAAANQADCggIMwAAAA==.Ashe:BAABNQAECoEXAAIBAAkJmR4XBQA0AwABAAkJmR4XBQA0AwAAAA==.',
At='Attabubble:BAAANQAECgEIAQABNQAECggIEgACAAAAAA==.Attaraxia:BAAANQAECggIEgAAAA==.',
Au='Aurelith:BAAANQADCgIIAwAAAA==.',
Av='Aviarra:BAAANQABCgUIBwAAAA==.',
Ay='Ayroon:BAAANQADCgUICAAAAA==.',
Ba='Bamfbutcher:BAAANQAECgUICAAAAA==.Barent:BAAANQADCgYIDAAAAA==.Barrimen:BAAANQAECgQIBQAAAA==.Bartolomew:BAAANQAECgMIAwAAAQ==.',
Be='Bedemere:BAAANQAECgIIAgAAAA==.Beepers:BAAANQAECgUICAAAAA==.Behodahlia:BAAANQADCggIFAAAAA==.Belfie:BAAANQAECgEIAQAAAA==.Berrylla:BAAANQABCgIIAwAAAA==.',
Bi='Bigmakk:BAAANQAECgQIBQAAAA==.Bimzelx:BAAANQADCgcIEAAAAA==.Bitterblood:BAAANQAECgIIAgAAAA==.',
Bl='Blastgamer:BAAANQADCggIEQAAAA==.Blondebeard:BAAANQAECgQIBAAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAAANQAECgIIAgAAAA==.',
Br='Bragontix:BAAANQAECgYICgAAAA==.Brewvoke:BAAANQAECgUICQAAAA==.Brightxan:BAAANQAECgEIAQAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECgQIBQACAAAAAA==.Bubbahunter:BAAANQAECgQIBQAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECgQIBQACAAAAAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAAANQAECgUIDgAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAAANQAFFAIIAwABNQAFFAUICgADAKAfAA==.Bussdefense:BAAANQADCgUICgAAAA==.Butterrs:BAAANQAECggIFQAAAQ==.Butterz:BAAANQAECgEIAQABNQAECggIFQACAAAAAA==.',
Ca='Caleian:BAAANQADCgQICgAAAA==.Caloren:BAAANQAECgIIBAAAAA==.Caorou:BAAANQADCgIIAgAAAA==.',
Ch='Charlyte:BAAANQAECgQIBAAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Cu='Cuigy:BAAANQADCggIFAAAAA==.',
Cy='Cyriene:BAAANQADCgYIEgAAAA==.',
Da='Dalio:BAAANQADCgYIBgAAAA==.Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAAANQAECgEIAQAAAA==.',
Dd='Ddeathchura:BAAANQAECgEIAQAAAA==.',
De='Deactrim:BAAANQAECgEIAgAAAA==.Deathrunner:BAAANQADCggICAAAAA==.Dema:BAAANQADCgMIAwAAAA==.Dendrada:BAAANQAECgEIAQAAAA==.Deuce:BAAANQADCggIEwAAAA==.',
Di='Dizimo:BAAANQADCgUIBQAAAA==.',
Do='Dogmeat:BAAANQAECgcICwABNQAFFAIIAgACAAAAAA==.',
Dr='Drakeshadows:BAAANQADCgIIAgAAAA==.Drchivago:BAAANQABCgMIBAAAAA==.',
Du='Duna:BAAANQADCggIFAAAAA==.Dungoofed:BAAANQADCgQIBAAAAA==.Duvidressra:BAAANQAECgcICwAAAA==.',
Dx='Dxmvn:BAAANQADCgQIBQAAAA==.',
Ed='Edisonn:BAAANQAECgYIDgAAAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgUICgAAAA==.Elentisa:BAAANQADCgYICAAAAA==.Elghinn:BAAANQAECgMIBAAAAA==.Elissaria:BAAANQADCgQIBAAAAA==.Ellastrasza:BAAANQAECgQIBQAAAA==.Ellie:BAAANQADCgcICwAAAA==.Elroy:BAAANQAECgQIBQAAAA==.',
Em='Emernantus:BAAANQAECgIIAgAAAA==.',
Er='Erazar:BAAANQAECgUIBwAAAA==.',
Es='Espy:BAAANQAECgMIBAAAAA==.',
Eu='Eunbyeol:BAAANQAECgUIBQAAAA==.',
Ev='Evee:BAAANQABCgQIBAAAAA==.',
Fa='Faeria:BAAANQAECgIIAgAAAA==.Fatnchunkydk:BAAANQADCggIFAAAAA==.',
Fe='Feeblemind:BAAANQADCggIFQAAAA==.Feli:BAAANQADCggIFAAAAA==.Fender:BAAANQADCggIFQAAAA==.',
Ff='Ffugntotems:BAAANQADCgcICwAAAA==.Ffviitifa:BAAANQADCgcICwAAAA==.',
Fi='Fingertoes:BAAANQAECgQIBwAAAA==.Fizzlerazz:BAAANQADCgUIBQAAAA==.',
Fl='Flatulatta:BAAANQAECgQICAAAAA==.Flyciful:BAAANQADCgcIBwAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQADCgUIBgABNQAECgEIAQACAAAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAAANQAECgQIBQAAAA==.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCgUICQAAAA==.Frodowagons:BAAANQAECggICAAAAA==.',
Fu='Fuglybaby:BAAANQADCgUIBQAAAA==.Fuhenhenka:BAAANQADCggICgAAAA==.',
Fw='Fwakos:BAAANQADCgYIEQAAAA==.',
Ga='Gakmonk:BAAANQADCgYIBgABNQAECgMIBAACAAAAAA==.Gakpaladin:BAAANQAECgMIBAAAAA==.Galthul:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.Garfyaz:BAAANQADCgYICwAAAA==.',
Ge='Gethael:BAAANQADCgIIAgAAAA==.',
Go='Goatroth:BAAANQADCgYIBgAAAA==.Golorious:BAAANQAECgUICAAAAA==.Goododie:BAAANQADCggIDwAAAA==.',
Gr='Grenas:BAAANQABCgMIBQAAAA==.Grippyweasle:BAAANQAECgEIAgAAAA==.Growlius:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
Gu='Gulaken:BAAANQAECgIIAwAAAA==.Guseva:BAAANQAECgEIAQAAAA==.Guttershark:BAAANQAECgUICQAAAA==.',
Ha='Hafnia:BAAANQADCgYICAAAAA==.Halliday:BAAANQADCggIFgAAAA==.Haoasakura:BAAANQAECgUICQAAAA==.Haylo:BAAANQAECgIIAgAAAA==.',
He='Healzforfood:BAAANQADCgEIAQAAAA==.Heap:BAAANQAECgMIAwABNQAECgQIBAACAAAAAA==.Heartlight:BAAANQADCgMIAwAAAA==.Helicobacter:BAAANQADCgMIAwAAAA==.Hewnoshaqa:BAAANQADCgQIBAAAAA==.Hexorcist:BAAANQAECgYIDQAAAA==.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAAANQADCgUIBwABNQAECgEIAQACAAAAAA==.',
Ho='Holyanne:BAAANQADCgQIAgAAAA==.Horous:BAAANQADCggIBwAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntrlicious:BAAANQAECgMICAAAAA==.',
Id='Idoshiftwork:BAAANQAECgUICAAAAA==.Idunno:BAAANQADCgUICAAAAA==.',
Ik='Ikazuchi:BAAANQAECgEIAQAAAA==.',
Il='Illcutabish:BAAANQAECggICgAAAA==.Illtank:BAAANQADCggIEAAAAA==.',
Im='Imk:BAAANQAECgEIAQAAAA==.',
Io='Iock:BAEANQAECgUIBQAAAA==.',
Ir='Ironarms:BAAANQAECgUIBwAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAAANQAECgYIBQAAAA==.',
Jo='Johnwarrior:BAAANQAECgQIBgAAAA==.Jorrix:BAAANQAECgIIAgAAAA==.',
Ju='Juduspriestt:BAAANQAECgEIAQAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgQIBgAAAA==.',
Ka='Kaaeko:BAAANQAECgUICwAAAA==.Kalerito:BAAANQAECgMIBAAAAA==.Kallythea:BAAANQADCggICAAAAA==.Kardie:BAAANQADCgQIBAABNQAECgUIBwACAAAAAA==.Karl:BAAANQADCggIEwAAAA==.Kaserr:BAABNQAECoEZAAMEAAkJ+SPPAgBBAwAEAAgJ+STPAgBBAwAFAAMJwR6gGQAQAQAAAA==.Kayserdh:BAAANQAECgUICAAAAA==.Kazaf:BAAANQAECgIIAwAAAA==.Kazarian:BAAANQADCgEIAQAAAA==.',
Ke='Kebru:BAAANQAECgIIAgAAAA==.Keitrek:BAAANQAECgMIBAAAAA==.Kelthias:BAAANQADCgUIBgAAAA==.Keyen:BAAANQAECgEIAQAAAA==.',
Ki='Kibalion:BAAANQADCggIEgAAAA==.Killbent:BAAANQADCgUIDgAAAA==.Kinnky:BAAANQADCggIEwAAAA==.Kino:BAAANQADCggIFAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAAANQAECgMIBAAAAA==.',
Ks='Ksp:BAAANQADCgQIBQAAAA==.',
Ku='Kugamoo:BAAANQAECgUICAAAAA==.Kulgan:BAAANQAECgYICQAAAA==.Kurgen:BAAANQADCggIFAAAAA==.Kuroda:BAAANQADCgYIBgAAAA==.',
La='Lamiah:BAAANQAECgEIAQAAAA==.',
Lc='Lckdown:BAAANQAECggIBgAAAA==.',
Le='Legomyegolas:BAAANQADCgYIBgAAAA==.',
Li='Livingkntpib:BAAANQADCggICAAAAA==.',
Lo='Loden:BAAANQAECgcICwAAAA==.Lodez:BAAANQAECgMIAwAAAA==.Loktarhogar:BAAANQAECgUIBQAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAAANQAECggIAQAAAA==.',
Lu='Luckyboi:BAAANQAECgYICQAAAA==.Lumeria:BAAANQAECgEIAQAAAA==.Lumina:BAAANQAECgMIAwAAAA==.Lusciifi:BAABNQAECoEXAAMGAAkJ6CNpAgC6AwAGAAkJ6CNpAgC6AwADAAMJPxY1HgCrAAAAAA==.',
Ly='Lykie:BAAANQAECgYICwAAAA==.Lynxic:BAAANQADCgQIBwABNQADCgUIBQACAAAAAA==.Lyone:BAAANQAECgEIAQAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lú']='Lúvaa:BAAANQAECgUICwAAAA==.',
Ma='Macavity:BAAANQADCgMIAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQADCgcIDgAAAA==.Magicwoman:BAAANQADCgYIDAAAAA==.Magikkisback:BAAANQADCgUIBQAAAA==.Magsh:BAAANQADCggIEwAAAA==.Mandorius:BAAANQAECgMIAgAAAA==.Marcos:BAAANQADCgIIAgAAAA==.Maverickdog:BAAANQAECgYICwAAAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQADCgcIDQACAAAAAA==.Meeshie:BAAANQAECgcIDQAAAA==.Melodrop:BAAANQAECggIBQAAAA==.',
Mi='Mikexfire:BAAANQAECgIIAwAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Misspell:BAAANQADCggIDAAAAA==.Miznewbooty:BAAANQAECgUICAAAAA==.',
Mo='Moochella:BAAANQADCggIFAAAAA==.Moojestic:BAAANQADCggIDwAAAA==.Moonq:BAAANQAECgEIAQAAAA==.Moosie:BAAANQAECgMIAwAAAA==.Mooska:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Moxflip:BAAANQAECgYIBwAAAA==.',
Mu='Muffy:BAAANQAECgEIAQAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Mythnarra:BAAANQAECgcIDgAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Na='Nadíne:BAAANQAECgUICgAAAA==.Nanukimon:BAAANQADCggIFAAAAA==.Naughtgelic:BAAANQADCgQIAwAAAA==.',
Ne='Nedgamingttv:BAEANQAECgEIAQAAAA==.Nevaera:BAAANQADCgYIBgAAAA==.',
Ni='Ni:BAAANQAECgQIBAAAAA==.Nick:BAABNQAECoEZAAIHAAkJOiHUAwB7AwAHAAkJOiHUAwB7AwAAAA==.Nikor:BAEANQADCgcIEQAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQADCggIDwAAAA==.Nomecoma:BAAANQAECgEIAQAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Noshom:BAAANQAECgIIAwAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ns='Nsyncrogue:BAAANQADCgQIBAAAAA==.',
Ny='Nymful:BAAANQADCggIFgAAAA==.',
['Nè']='Nèlo:BAAANQADCggIFAAAAA==.',
Ob='Obianstrider:BAAANQADCgUIBwAAAA==.',
Oc='Oceanspell:BAAANQAECgQICAAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAAANQAECgUICAAAAA==.',
On='Onlytoez:BAAANQADCggICAABNQAECgcIDQACAAAAAA==.',
Or='Orave:BAAANQADCgcIEQAAAA==.Oromë:BAAANQABCgQIBAAAAA==.Orzik:BAAANQADCgcIBwAAAA==.',
Os='Ostena:BAAANQADCggIGgAAAA==.Osteole:BAAANQADCggIEgABNQADCggIGgACAAAAAA==.',
Ou='Oulawdpriest:BAABNQAECoEWAAMIAAgJRRVQDABkAgAIAAgJRRVQDABkAgAJAAEJYxP2YwBCAAAAAA==.',
Ov='Overture:BAAANQADCgQIBgAAAA==.',
Ow='Owthatburns:BAAANQADCgYIBgAAAA==.',
Pa='Pakszdude:BAAANQADCgUIBQAAAA==.Pandamonious:BAAANQADCggICAABNQAECgEIAgACAAAAAA==.Papawoof:BAAANQADCgEIAQABNQAECgYIDQACAAAAAA==.Parkour:BAAANQADCgcIDQAAAA==.Paullyfists:BAAANQAECgQIBwAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAgAAAA==.',
Po='Popkorn:BAABNQAECoEZAAMKAAkJaSVGAQC5AwAKAAkJtiRGAQC5AwALAAIJbSJjCQDQAAAAAA==.Popkourne:BAAANQAECgEIAQABNQAECgkJGQAKAGklAA==.Poplocks:BAAANQADCgQIBAAAAA==.Porrana:BAAANQADCggIEQAAAA==.Powaqa:BAAANQADCggIGQAAAA==.',
Pr='Praetorian:BAAANQAECgMIAwAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAAANQAECgUIBQAAAA==.Quethelos:BAAANQADCgcIEQAAAA==.Quickbrew:BAAANQADCgQIBAAAAA==.Quickspell:BAAANQAECgUICQAAAA==.',
Ra='Raalcar:BAAANQADCgUIBQAAAA==.Raedyyn:BAAANQADCggIFAAAAA==.Ragarninn:BAAANQADCgUIBQABNQAECggIDAACAAAAAA==.Ragendecay:BAAANQADCggIDwAAAA==.Ragequits:BAACNQAFFIEMAAIMAAYJQyN5AAB9AgAMAAYJQyN5AAB9AgA1AAQKgRoAAgwACQn2JcMBANMDAAwACQn2JcMBANMDAAAA.Rakshassa:BAAANQAECgEIAQAAAA==.Rawkphyst:BAAANQADCgQIAgAAAA==.Razrscale:BAAANQAECgEIAQAAAA==.',
Re='Redhuntsman:BAAANQADCgUICwAAAA==.Regrow:BAAANQADCgcIBwABNQADCgcIDQACAAAAAA==.Reska:BAAANQADCgUICgAAAA==.',
Rh='Rholdentodor:BAAANQADCgEIAQABNQAECgQIBQACAAAAAA==.',
Ri='Rindorin:BAAANQADCggICwAAAA==.Ritarepulsa:BAAANQADCgYIDAAAAA==.',
Ro='Rohra:BAAANQAECgIIAgAAAA==.Rozynwen:BAAANQADCgQIBQAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQAECgEIAQAAAA==.Rukuna:BAAANQAECgEIAQAAAA==.Runecast:BAAANQAECgUIBQAAAA==.',
Sa='Saelyrinth:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Sarapheena:BAAANQAECgUICAAAAA==.Sarouk:BAAANQAECgUIBQAAAA==.Satansbride:BAAANQADCgQIBAABNQADCgUIBQACAAAAAA==.Saterli:BAAANQAECgcIBwAAAA==.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAAANQAECgEIAgAAAA==.Sayygurl:BAAANQADCgMIBAAAAA==.',
Sc='Scalvert:BAAANQAECgQIBQAAAA==.Scalypanda:BAAANQAECgUICAAAAA==.Scamander:BAAANQAECgcICAAAAA==.Scoobs:BAAANQADCgQIBAABNQADCgYICAACAAAAAA==.Sculi:BAAANQAECgMIAwAAAA==.',
Se='Seiishiro:BAAANQADCgcIDQAAAA==.Seldon:BAAANQADCggIFgAAAA==.Senyor:BAAANQAECggIAQAAAA==.Seradormi:BAAANQADCgMIAwAAAA==.Seraphiel:BAAANQADCggIEgABNQADCgIIAgACAAAAAA==.',
Sh='Shadowpaksz:BAAANQAECgEIAQAAAA==.Shadowsneak:BAAANQADCggIEwAAAA==.Shadowvixen:BAAANQADCggIDwAAAA==.Shaelistra:BAAANQADCggIFgAAAA==.Shalilama:BAAANQAECggIDAAAAA==.Shamboli:BAAANQADCgEIAQAAAA==.Shenderp:BAAANQADCggIEwAAAA==.Shinerbock:BAAANQAECgUIBgAAAA==.Shockitti:BAAANQADCgMIAwAAAA==.Shtark:BAAANQADCgUIBgAAAA==.',
Si='Silshara:BAAANQAECgcIDQAAAA==.Silverjustis:BAAANQAECgEIAQAAAA==.Siwe:BAAANQAECgMIBAAAAA==.Six:BAAANQAECgIIAgABNQAECgMIAwACAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skribblez:BAAANQAECgMIBgAAAA==.Skyanna:BAAANQADCgUICAAAAA==.',
Sl='Sloot:BAAANQADCgcICgAAAA==.',
Sn='Sneasel:BAAANQAECgMIBAABNQAECgQIBAACAAAAAA==.Snoogins:BAAANQADCgUIBQAAAA==.',
So='Sockszz:BAAANQAECgUICwAAAA==.Songblade:BAAANQABCgEIAQAAAA==.Soulsy:BAAANQAECgYIDgAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAAANQAECgIIAgAAAA==.',
Sp='Splendorae:BAAANQAECgUIBgAAAA==.Sprints:BAAANQAECgQIBQAAAA==.Spritz:BAAANQAECgUICAAAAA==.Sprucewillis:BAAANQADCgMIAwABNQADCgUIBQACAAAAAA==.Spyderelite:BAAANQAECgQIBgAAAA==.',
Sq='Squirrel:BAAANQAECgMIBAAAAA==.',
Ss='Ssuperss:BAAANQADCgQIBQAAAA==.',
St='Stabbot:BAAANQADCggIDgABNQAECgEIAQACAAAAAA==.Starblood:BAAANQABCgMIAwAAAA==.Starspeaker:BAAANQADCgYICgAAAA==.Stompmyballs:BAAANQAECgIIAwABNQAFFAYIDAAMAEMjAA==.Stoogotz:BAAANQADCgIIBAAAAA==.Studlebane:BAAANQABCgIIAgABNQAECgEIAQACAAAAAA==.Studlepalm:BAAANQAECgEIAQAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAAANQAECgUICAAAAA==.Supersheep:BAAANQADCgYIBgAAAA==.Suvien:BAAANQADCgEIAQAAAA==.',
Sy='Sylvarian:BAAANQADCggIEwAAAA==.Sylvinna:BAAANQADCgUIBwAAAA==.',
Ta='Tagda:BAAANQADCggICAAAAA==.Taterdotz:BAAANQADCgQIBgAAAA==.Tatortwats:BAAANQAFFAEIAQAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tephine:BAAANQAECgQIBwAAAA==.Tepicoyotl:BAAANQAECgUICAAAAA==.',
Th='Thebigkitti:BAAANQADCgEIAQAAAA==.Thelonecone:BAAANQAECggIEQAAAA==.Theodor:BAAANQADCgcIBwAAAA==.Theraphee:BAAANQADCgQICgAAAA==.Therym:BAAANQADCgEIAQABNQAECgcICQACAAAAAA==.Thomwizard:BAAANQADCggIFAAAAA==.Thormorn:BAAANQADCggICQAAAA==.Thunnha:BAAANQADCgYIBwAAAA==.',
Ti='Tierali:BAAANQADCgYIBgAAAA==.Tio:BAAANQADCggIEAAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAAANQAECgEIAQAAAA==.Torrinchaos:BAAANQADCgQIBAAAAA==.Totemkiller:BAAANQAECgEIAQAAAA==.',
Tr='Traael:BAAANQAECgEIAQAAAA==.Treesap:BAAANQAECgUIBgAAAA==.Trinityeve:BAAANQADCgcIEgAAAA==.Trmz:BAAANQAECgYICgAAAA==.Trnzlock:BAAANQAECgQIBwABNQAECgYICgACAAAAAA==.',
Tu='Tulanii:BAAANQADCgIIAgAAAA==.Tumble:BAAANQAECgEIAQAAAA==.',
Tw='Twinkie:BAAANQAECgEIAQAAAA==.Twodogz:BAAANQAECgIIAgAAAA==.',
Ty='Tyious:BAAANQAECgUICAAAAA==.Tyndara:BAAANQADCgcIEwAAAA==.',
Ub='Ubavoke:BAAANQADCgcIDQAAAA==.',
Uk='Ukita:BAAANQAFFAEIAQAAAA==.',
Ur='Ursane:BAAANQAECgUICAAAAA==.Ursully:BAAANQADCggIEwAAAA==.',
Uz='Uzi:BAAANQAECgEIAQAAAA==.',
Va='Valentíne:BAAANQADCgYICQAAAA==.Valhalla:BAAANQADCgYICgAAAA==.Vanncint:BAAANQADCggIEAAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Vexus:BAAANQAFFAEIAQAAAA==.',
Vi='Vixly:BAAANQADCgUIBgAAAA==.',
Vl='Vladios:BAAANQAECgEIAQAAAA==.',
Vo='Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Walolas:BAAANQADCgcIDQAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgcIEAAAAA==.Watchmeburst:BAAANQADCgYICAAAAA==.',
Wh='Whaler:BAAANQAECggIAQAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Windowskey:BAAANQAECgMIAwABNQAECgUIBQACAAAAAA==.',
Wu='Wuzntmyfault:BAAANQADCgcIDQAAAA==.',
Wy='Wyldfyire:BAAANQAECgEIAQAAAA==.',
Xa='Xaven:BAAANQAECgEIAQAAAA==.Xavenuke:BAAANQADCgcIDQABNQAECgEIAQACAAAAAA==.',
Xi='Xiaotao:BAAANQAECgMIAwAAAA==.',
Yo='Yoga:BAAANQADCgcIDgAAAA==.',
Za='Zabra:BAAANQADCgYIDQAAAA==.Zahshia:BAAANQADCgcIEQAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAAANQAECgcIDgAAAA==.Zaylian:BAAANQAECgUICQAAAA==.Zayragossa:BAAANQAECgUICQAAAA==.Zayrah:BAAANQADCggIEgABNQAECgUICQACAAAAAA==.',
Ze='Zeerkk:BAAANQAECgMIBAAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.',
Zi='Zirilian:BAAANQADCgQICAABNQAECgEIAQACAAAAAA==.',
Zo='Zoomzoom:BAAANQAECgEIAQABNQAECggIFgAIAEUVAA==.',
Zu='Zulkraa:BAAANQADCgcICQAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Ài']='Àirén:BAAANQAECgEIAQAAAA==.',
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
