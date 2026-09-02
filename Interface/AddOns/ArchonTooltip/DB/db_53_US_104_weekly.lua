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

local lookup = {'Unknown-Unknown','Paladin-Protection','Warrior-Arms',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acuminada:BAAANQADCgIIAgAAAA==.Acuna:BAAANQAECgEIAQAAAA==.',
Ad='Adison:BAAANQADCgIIAgAAAA==.',
Af='Affliction:BAAANQAECgIIAgAAAA==.',
Ai='Airz:BAAANQADCggIDwAAAA==.',
Ak='Akâkiôs:BAAANQADCgYIDAAAAA==.',
Al='Aladorman:BAAANQADCgYIBgAAAA==.Alamo:BAAANQADCgYIBwAAAA==.Albertlin:BAAANQADCgQIBQAAAA==.Alexinar:BAAANQADCgYICQAAAA==.',
Am='Amakuagsak:BAAANQADCgYICwAAAA==.Amicus:BAAANQADCgYIDAAAAA==.Ampmage:BAAANQADCgUIBgAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.',
Ap='Apollo:BAAANQAECgEIAQAAAA==.Apolynnæ:BAAANQAECgQIBAAAAA==.',
Ar='Araniss:BAAANQADCgcIDAAAAA==.Arasthel:BAAANQADCgcIDAAAAA==.Aratrath:BAAANQAECgMIAwAAAA==.Aryasilly:BAAANQAECgEIAQAAAA==.',
As='Asdi:BAAANQADCggIKwAAAA==.Ashe:BAAANQAECggIDQAAAA==.',
At='Attabubble:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Attaraxia:BAAANQAECgYICgAAAA==.',
Au='Aurelith:BAAANQADCgIIAwAAAA==.',
Av='Aviarra:BAAANQABCgQIBQAAAA==.',
Ay='Ayroon:BAAANQADCgUIBwAAAA==.',
Ba='Bamfbutcher:BAAANQAECgMIAwAAAA==.Barent:BAAANQADCgQIBgAAAA==.Barrimen:BAAANQAECgEIAQAAAA==.Bartolomew:BAAANQADCggIDgAAAQ==.',
Be='Bedemere:BAAANQADCggIDgAAAA==.Beepers:BAAANQAECgMIAwAAAA==.Behodahlia:BAAANQADCgcIDAAAAA==.Belfie:BAAANQADCgcICwAAAA==.',
Bi='Bigdemon:BAAANQADCggIDgAAAA==.Bigmakk:BAAANQAECgEIAQAAAA==.Bimzelx:BAAANQADCgYICQAAAA==.Bitterblood:BAAANQADCggIFgAAAA==.',
Bl='Blastgamer:BAAANQADCgYICQAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAAANQADCggIDAAAAA==.',
Br='Bragontix:BAAANQAECgYIBwAAAA==.Brewvoke:BAAANQAECgUICQAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Bubbahunter:BAAANQAECgQIBAAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAAANQAECgUICQAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAAANQAFFAEIAQABNQAFFAQIBgACAGQcAA==.Bussdefense:BAAANQADCgQICAAAAA==.Butterrs:BAAANQAECgcIDQAAAQ==.Butterz:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.',
Ca='Caleian:BAAANQADCgQIBgAAAA==.Caloren:BAAANQAECgIIAwAAAA==.Caorou:BAAANQADCgIIAgAAAA==.',
Ch='Charlyte:BAAANQADCggICAAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Cu='Cuigy:BAAANQADCgcIDAAAAA==.',
Cy='Cyriene:BAAANQADCgYIDAAAAA==.',
Da='Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAAANQADCgcIDAAAAA==.',
Dd='Ddeathchura:BAAANQADCgcIDQAAAA==.',
De='Deactrim:BAAANQAECgEIAQAAAA==.Deathrunner:BAAANQADCggICAAAAA==.Dema:BAAANQADCgMIAwAAAA==.Dendrada:BAAANQADCgcIDQAAAA==.Deuce:BAAANQADCgYICwAAAA==.',
Di='Dizimo:BAAANQADCgUIBQAAAA==.',
Do='Dogmeat:BAAANQAECgYICQABNQAECgcICwABAAAAAA==.',
Dr='Drchivago:BAAANQABCgIIAgAAAA==.',
Du='Duna:BAAANQADCgYIDAAAAA==.Dungoofed:BAAANQADCgQIBAAAAA==.Duvidressra:BAAANQAECgMIAwAAAA==.',
Dx='Dxmvn:BAAANQADCgIIAgAAAA==.',
Ed='Edisonn:BAAANQAECgUICAAAAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgQIBQAAAA==.Elghinn:BAAANQAECgEIAQAAAA==.Ellastrasza:BAAANQAECgEIAQAAAA==.Ellie:BAAANQADCgcICwAAAA==.Elroy:BAAANQAECgEIAQAAAA==.',
Em='Emernantus:BAAANQADCggIDwAAAA==.',
Er='Erazar:BAAANQAECgIIAgAAAA==.',
Es='Espy:BAAANQAECgMIBAAAAA==.',
Eu='Eunbyeol:BAAANQADCggIEAAAAA==.',
Fa='Faeria:BAAANQADCggIDQAAAA==.Fatnchunkydk:BAAANQADCgYIDAAAAA==.',
Fe='Feeblemind:BAAANQADCgcIDQAAAA==.Feli:BAAANQADCgcIDAAAAA==.Fender:BAAANQADCgcIDQAAAA==.',
Ff='Ffugntotems:BAAANQADCgQIBAAAAA==.Ffviitifa:BAAANQADCgQIBAAAAA==.',
Fi='Fingertoes:BAAANQAECgQIAwAAAA==.',
Fl='Flatulatta:BAAANQADCggIEAAAAA==.Flyciful:BAAANQABCgEIAQAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQADCgUIBgAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAAANQAECgQIBQAAAA==.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCgUIBwAAAA==.',
Fu='Fuglybaby:BAAANQADCgQIBAAAAA==.Fuhenhenka:BAAANQADCgYIBgAAAA==.',
Fw='Fwakos:BAAANQADCgYICwAAAA==.',
Ga='Gakmonk:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Gakpaladin:BAAANQAECgEIAQAAAA==.Galthul:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Garfyaz:BAAANQADCgYICwAAAA==.',
Go='Golorious:BAAANQAECgMIAwAAAA==.Goododie:BAAANQADCgYIBwAAAA==.',
Gr='Grippyweasle:BAAANQAECgEIAQAAAA==.Growlius:BAAANQADCgYIBgABNQADCgcICwABAAAAAA==.',
Gu='Gulaken:BAAANQAECgEIAQAAAA==.Guseva:BAAANQAECgEIAQAAAA==.Guttershark:BAAANQAECgQIBAAAAA==.',
Ha='Hafnia:BAAANQADCgQIBAAAAA==.Halliday:BAAANQADCggIEgAAAA==.Haoasakura:BAAANQAECgIIBAAAAA==.Haylo:BAAANQADCgYIBgAAAA==.',
He='Healzforfood:BAAANQADCgEIAQAAAA==.Heap:BAAANQAECgMIAwAAAA==.Heartlight:BAAANQADCgMIAwAAAA==.Hewnoshaqa:BAAANQADCgQIBAAAAA==.Hexorcist:BAAANQAECgYIBwAAAA==.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAAANQADCgUIBwABNQAECgEIAQABAAAAAA==.',
Ho='Holyanne:BAAANQABCgQIBAAAAA==.Horous:BAAANQADCggIBwAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntrlicious:BAAANQAECgEIAgAAAA==.',
Id='Idoshiftwork:BAAANQAECgMIAwAAAA==.Idunno:BAAANQADCgMIAwAAAA==.',
Ik='Ikazuchi:BAAANQADCgYICgAAAA==.',
Il='Illcutabish:BAAANQAECgcIAwAAAA==.Illtank:BAAANQADCgIIAgAAAA==.',
Im='Imk:BAAANQADCgcIDQAAAA==.',
Io='Iock:BAEANQADCgYIBgAAAA==.',
Ir='Ironarms:BAAANQAECgIIAgAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAAANQADCgYICgAAAA==.',
Jo='Johnwarrior:BAAANQADCggIDgAAAA==.Jorrix:BAAANQADCgUICQAAAA==.',
Ju='Juduspriestt:BAAANQADCgYIDgAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgQIBQAAAA==.',
Ka='Kaaeko:BAAANQAECgQIBgAAAA==.Kalerito:BAAANQAECgEIAQAAAA==.Karl:BAAANQADCgYICwAAAA==.Kaserr:BAAANQAECggIDgAAAA==.Kayserdh:BAAANQAECgUICAAAAA==.Kazaf:BAAANQAECgIIAgAAAA==.Kazarian:BAAANQADCgEIAQAAAA==.',
Ke='Keitrek:BAAANQAECgEIAQAAAA==.Kelthias:BAAANQADCgIIAgAAAA==.Keyen:BAAANQADCgcIDQAAAA==.',
Ki='Kibalion:BAAANQADCgcICgAAAA==.Killbent:BAAANQADCgUICQAAAA==.Kinnky:BAAANQADCgYICwAAAA==.Kino:BAAANQADCgYIDAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAAANQAECgEIAQAAAA==.',
Ks='Ksp:BAAANQADCgQIBQAAAA==.',
Ku='Kugamoo:BAAANQAECgMIAwAAAA==.Kulgan:BAAANQAECgQIBAAAAA==.Kurgen:BAAANQADCgYIDAAAAA==.Kuroda:BAAANQADCgEIAQAAAA==.',
La='Lamiah:BAAANQADCgYIBgAAAA==.',
Lc='Lckdown:BAAANQADCgMIAwAAAA==.',
Le='Legomyegolas:BAAANQADCgYIBgAAAA==.',
Lo='Loden:BAAANQAECgQIBAAAAA==.Loktarhogar:BAAANQADCggIDAAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAAANQADCgcIDAAAAA==.',
Lu='Luckyboi:BAAANQAECgMIAwAAAA==.Lumeria:BAAANQADCgUIBgAAAA==.Lumina:BAAANQADCggIDgAAAA==.Lusciifi:BAAANQAFFAEIAQAAAA==.',
Ly='Lykie:BAAANQAECgQIBgAAAA==.Lynxic:BAAANQADCgQIBwAAAA==.Lyone:BAAANQADCgYICgAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lú']='Lúvaa:BAAANQAECgQIBgAAAA==.',
Ma='Macavity:BAAANQADCgMIAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQADCgUIBQAAAA==.Magicwoman:BAAANQADCgYIBgAAAA==.Magikkisback:BAAANQADCgUIBQAAAA==.Magsh:BAAANQADCgcICwAAAA==.Mandorius:BAAANQADCgQIBAAAAA==.Marcos:BAAANQADCgIIAgAAAA==.Maverickdog:BAAANQAECgQIBQAAAA==.',
Mc='Mchammerwork:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Meeshie:BAAANQAECgUIBgAAAA==.',
Mi='Mikexfire:BAAANQAECgEIAQAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Mildchaos:BAAANQADCgEIAQAAAA==.Misspell:BAAANQADCgQIBAAAAA==.Miznewbooty:BAAANQAECgMIAwAAAA==.',
Mo='Moochella:BAAANQADCgcIDAAAAA==.Moojestic:BAAANQADCggIDQAAAA==.Moonq:BAAANQADCgcIDQAAAA==.Mooska:BAAANQAECgEIAQAAAA==.Moxflip:BAAANQAECgEIAQAAAA==.',
Mu='Muffy:BAAANQADCgcICwAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Mythnarra:BAAANQAECgYIBwAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAAAAA==.',
Na='Nadíne:BAAANQAECgQIBQAAAA==.Nanukimon:BAAANQADCgYIDAAAAA==.Naughtgelic:BAAANQADCgQIAwAAAA==.',
Ne='Nedgamingttv:BAEANQADCgUIBQABNQADCgUIBgABAAAAAA==.Nevaera:BAAANQADCgYIBgAAAA==.',
Ni='Ni:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.Nick:BAAANQAECgcIDwAAAA==.Nikor:BAEANQADCgUICgAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQADCgYIBwAAAA==.Nomecoma:BAAANQADCgcICwAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Noshom:BAAANQAECgEIAQAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ny='Nymful:BAAANQADCggIDgAAAA==.',
['Nè']='Nèlo:BAAANQADCgcIDAAAAA==.',
Ob='Obianstrider:BAAANQADCgQIBQAAAA==.',
Oc='Oceanspell:BAAANQAECgQIBAAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAAANQAECgMIAwAAAA==.',
On='Onlytoez:BAAANQADCggICAABNQAECgUIBgABAAAAAA==.',
Or='Orave:BAAANQADCgUICgAAAA==.Orzik:BAAANQADCgQIBAAAAA==.',
Os='Ostena:BAAANQADCgcIEgAAAA==.Osteole:BAAANQADCgYICgABNQADCgcIEgABAAAAAA==.',
Ou='Oulawdpriest:BAAANQAECgcIDQAAAA==.',
Ov='Overture:BAAANQADCgEIAQAAAA==.',
Pa='Pandamonious:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Parkour:BAAANQADCgYICAAAAA==.Paullyfists:BAAANQAECgMIAwAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAQAAAA==.',
Po='Popkorn:BAAANQAECggIDgAAAA==.Popkourne:BAAANQAECgEIAQABNQAECggIDgABAAAAAA==.Porrana:BAAANQADCgYICQAAAA==.Powaqa:BAAANQADCgcIEgAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAAANQADCggICAAAAA==.Quethelos:BAAANQADCgQICQAAAA==.Quickspell:BAAANQAECgQIBAAAAA==.',
Ra='Raedyyn:BAAANQADCgcIDAAAAA==.Ragendecay:BAAANQADCgcIBwAAAA==.Ragequits:BAABNQAFFIEGAAIDAAUJwR5EAAAHAgADAAUJwR5EAAAHAgAAAA==.Rakshassa:BAAANQAECgEIAQAAAA==.Razrscale:BAAANQADCgUIBwAAAA==.',
Re='Redhuntsman:BAAANQADCgQIBgAAAA==.Reska:BAAANQADCgQIBwAAAA==.',
Rh='Rholdentodor:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.',
Ri='Rindorin:BAAANQADCggICAAAAA==.Ritarepulsa:BAAANQADCgYICAAAAA==.',
Ro='Rohra:BAAANQADCggIDwAAAA==.Rozynwen:BAAANQADCgMIBAAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQADCgEIAQAAAA==.Rukuna:BAAANQADCgYIDAAAAA==.Runecast:BAAANQADCggICAAAAA==.',
Sa='Saelyrinth:BAAANQADCgUIBQABNQADCgUIBgABAAAAAA==.Sarapheena:BAAANQAECgMIAwAAAA==.Sarouk:BAAANQADCggIDgAAAA==.Satansbride:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Saterli:BAAANQADCgYIBgAAAA==.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAAANQAECgEIAQAAAA==.Sayygurl:BAAANQADCgMIBAAAAA==.',
Sc='Scalvert:BAAANQADCggICAAAAA==.Scalypanda:BAAANQAECgMIAwAAAA==.Scamander:BAAANQAECgcIAwAAAA==.Scoobs:BAAANQADCgQIBAAAAA==.Sculi:BAAANQADCgcIDQAAAA==.',
Se='Seiishiro:BAAANQADCgcIDAAAAA==.Seldon:BAAANQADCggIDgAAAA==.Senyor:BAAANQADCgcIDQAAAA==.Seradormi:BAAANQADCgMIAwAAAA==.Seraphiel:BAAANQADCgYICgABNQADCgIIAgABAAAAAA==.',
Sh='Shadowpaksz:BAAANQADCgYICAAAAA==.Shadowsneak:BAAANQADCgYICwAAAA==.Shadowvixen:BAAANQADCgQIBwAAAA==.Shaelistra:BAAANQADCggIDgAAAA==.Shalilama:BAAANQAECgUIBQAAAA==.Shamboli:BAAANQADCgEIAQAAAA==.Shenderp:BAAANQADCgYICwAAAA==.Shinerbock:BAAANQAECgEIAQAAAA==.Shtark:BAAANQADCgMIBAAAAA==.',
Si='Silshara:BAAANQAECgQIBgAAAA==.Silverjustis:BAAANQADCgcIDQAAAA==.Siwe:BAAANQAECgEIAQAAAA==.Six:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skribblez:BAAANQAECgIIBAAAAA==.Skyanna:BAAANQADCgIIAwAAAA==.',
Sl='Sloot:BAAANQADCgcICgAAAA==.',
Sn='Sneasel:BAAANQAECgMIBAAAAA==.Snoogins:BAAANQADCgUIBQAAAA==.',
So='Sockszz:BAAANQAECgMIBgAAAA==.Soulsy:BAAANQAECgUICAAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAAANQADCggIDAAAAA==.',
Sp='Splendorae:BAAANQAECgEIAQAAAA==.Sprints:BAAANQAECgEIAQAAAA==.Spritz:BAAANQAECgQIBAAAAA==.Spyderelite:BAAANQAECgIIAgAAAA==.',
Sq='Squirrel:BAAANQAECgEIAQAAAA==.',
Ss='Ssuperss:BAAANQADCgQIBAAAAA==.',
St='Stabbot:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Starblood:BAAANQABCgEIAQAAAA==.Starspeaker:BAAANQADCgYICgAAAA==.Stompmyballs:BAAANQAECgIIAgABNQAFFAUIBgADAMEeAA==.Studlepalm:BAAANQADCgUICwAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAAANQAECgMIAwAAAA==.Supersheep:BAAANQADCgUIBQAAAA==.',
Sy='Sylvarian:BAAANQADCgcICwAAAA==.Sylvinna:BAAANQADCgIIAgAAAA==.',
Ta='Tagda:BAAANQADCggICAAAAA==.Taterdotz:BAAANQADCgIIAgAAAA==.Tatortwats:BAAANQAECgEIAwAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tephine:BAAANQAECgMIAwAAAA==.Tepicoyotl:BAAANQAECgMIAwAAAA==.',
Th='Thelonecone:BAAANQAECgYICAAAAA==.Theodor:BAAANQADCgYIBgAAAA==.Theraphee:BAAANQADCgQIBgAAAA==.Therym:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Thomwizard:BAAANQADCgYIDAAAAA==.Thormorn:BAAANQADCgcICQAAAA==.Thunnha:BAAANQADCgYIBgAAAA==.',
Ti='Tio:BAAANQADCggICAAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAAANQAECgEIAQAAAA==.Totemkiller:BAAANQADCggIDwAAAA==.',
Tr='Traael:BAAANQAECgEIAQAAAA==.Treesap:BAAANQAECgEIAQAAAA==.Trinityeve:BAAANQADCgYICwAAAA==.Trmz:BAAANQAECgYIBgAAAA==.Trnzlock:BAAANQAECgMIAwABNQAECgYIBgABAAAAAA==.',
Tu='Tulanii:BAAANQADCgIIAgAAAA==.Tumble:BAAANQADCgcIDQAAAA==.',
Tw='Twinkie:BAAANQAECgEIAQAAAA==.Twodogz:BAAANQADCggIDwAAAA==.',
Ty='Tyious:BAAANQAECgMIAwAAAA==.Tyndara:BAAANQADCgYIDAAAAA==.',
Ub='Ubavoke:BAAANQADCgcICwAAAA==.',
Uk='Ukita:BAAANQAECgQIBQAAAA==.',
Ur='Ursane:BAAANQAECgMIAwAAAA==.Ursully:BAAANQADCgYICwAAAA==.',
Uz='Uzi:BAAANQADCgcIDQAAAA==.',
Va='Valentíne:BAAANQADCgUIBgAAAA==.Vanncint:BAAANQADCgYIDAAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Vexus:BAAANQAECgYIBgAAAA==.',
Vi='Vixly:BAAANQADCgQIBAAAAA==.',
Vl='Vladios:BAAANQADCgcIDQAAAA==.',
Vo='Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Walolas:BAAANQADCgcIDQAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgYICQAAAA==.Watchmeburst:BAAANQADCgYICAAAAA==.',
Wh='Whaler:BAAANQADCgcIDQAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.Windowskey:BAAANQAECgMIAwABNQADCggIDgABAAAAAA==.',
Wu='Wuzntmyfault:BAAANQADCgYICwAAAA==.',
Wy='Wyldfyire:BAAANQADCgYIBgAAAA==.',
Xa='Xavenuke:BAAANQADCgcIDQAAAA==.',
Xi='Xiaotao:BAAANQADCgYIBgAAAA==.',
Yo='Yoga:BAAANQADCgYIBwAAAA==.',
Za='Zabra:BAAANQADCgUIBwAAAA==.Zahshia:BAAANQADCgUICgAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAAANQAECgQIBwAAAA==.Zaylian:BAAANQAECgQIBAAAAA==.Zayragossa:BAAANQAECgQIBAAAAA==.Zayrah:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ze='Zeerkk:BAAANQAECgEIAQAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.',
Zi='Zirilian:BAAANQADCgQIBAABNQADCgYIDgABAAAAAA==.',
Zo='Zoomzoom:BAAANQADCgcIDQABNQAECgcIDQABAAAAAA==.',
Zu='Zulkraa:BAAANQADCgIIAgAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Åb']='Åbon:BAAANQADCgYICgAAAA==.',
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
