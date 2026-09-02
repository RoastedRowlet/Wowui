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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acks:BAAANQADCgYICgABNQAECgcICgABAAAAAA==.',
Ae='Aedra:BAAANQAECgEIAQAAAA==.Aex:BAAANQAECgcICgAAAA==.',
Ah='Ahnkhano:BAAANQADCgcIBwAAAA==.',
Ai='Ainge:BAAANQADCgYIBgAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAAANQAECggIDgAAAA==.',
Al='Allistrana:BAAANQADCgcIDQAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.Amairis:BAAANQADCgYICwAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAAANQAECgQIBQAAAA==.',
Au='Auranar:BAAANQADCgYICQAAAA==.Aurelya:BAAANQADCgIIAgAAAA==.Aurilia:BAAANQADCgYICAAAAA==.',
Av='Avanicus:BAAANQADCggIDgAAAA==.Aven:BAAANQADCgUIBQAAAA==.Avernas:BAAANQADCgcIBwAAAA==.',
Ax='Axellent:BAAANQADCgYIBgABNQAECgcICgABAAAAAA==.Axiomlegacy:BAAANQAECgIIAwAAAA==.',
Az='Azulien:BAAANQADCgYIDAAAAA==.',
Ba='Banderblitz:BAAANQAECgIIAgAAAA==.Bar:BAAANQAECgYICwAAAA==.',
Be='Bearlyshady:BAAANQAECgQIBQAAAA==.Bellarina:BAAANQADCgYICwAAAA==.Bellatrixie:BAAANQADCgYICwAAAA==.Beriadhwen:BAAANQADCgYICQAAAA==.Bermy:BAAANQAECgEIAQAAAA==.Bewildert:BAAANQADCgEIAQAAAA==.',
Bi='Bigjaina:BAAANQAECgQIBQAAAA==.Biku:BAAANQADCgYIBQAAAA==.',
Bl='Blackhawkdk:BAAANQAECgMIAwAAAA==.Blende:BAAANQADCggIDwAAAA==.Bloodshadow:BAAANQADCggIDwAAAA==.',
Br='Breakcooloz:BAAANQAECgQIBgABNQAECgYIDAABAAAAAA==.Brooce:BAAANQADCggIDwAAAA==.',
Bu='Burstinurass:BAAANQAECgYIDAAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Carbonight:BAAANQAECgcIDQAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.Cellyne:BAAANQADCgYIBQAAAA==.',
Ch='Chaoswind:BAAANQAECgQIBQAAAA==.Chelives:BAEANQADCgcIDQAAAA==.Cherpnome:BAAANQADCgYICQABNQADCggIDgABAAAAAA==.Cherubix:BAAANQADCgMIAwABNQADCggIDgABAAAAAA==.Chromus:BAAANQAECgUIBQAAAA==.',
Ci='Cires:BAAANQAECgEIAQAAAA==.',
Co='Colanasou:BAAANQADCgYICAAAAA==.Coldbattler:BAAANQADCgIIAgAAAA==.Convictions:BAAANQAECgYICwABNQAECggICwABAAAAAA==.Corrick:BAAANQADCgYICgAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQADCgQIBAAAAQ==.',
Cy='Cydric:BAAANQADCgcIBwAAAA==.',
Da='Daarrkstar:BAAANQADCgcIDQABNQADCggIDwABAAAAAA==.Dakaryn:BAAANQADCgUIBQAAAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathrival:BAAANQABCgIIAgAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Demonkare:BAAANQADCgIIAwABNQAECgQIBQABAAAAAA==.Demoray:BAAANQAFFAEIAQAAAA==.Dethrone:BAAANQADCgUIBgAAAA==.Deus:BAAANQAECgQICwAAAA==.',
Di='Dinosocks:BAAANQADCgMIAwABNQAFFAEIAQABAAAAAA==.Dirtydragon:BAAANQADCgcIDQAAAA==.Divinedecay:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.',
Do='Donoraginn:BAAANQADCgIIAgABNQADCgMIBgABAAAAAA==.Donos:BAAANQADCgMIBgAAAA==.Dotgenerate:BAAANQADCggIDgAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQADCggIDAAAAA==.Drathiel:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Drwho:BAAANQADCgYIDAAAAA==.Drëëxx:BAAANQADCgUICgAAAA==.',
['Dî']='Dîxon:BAAANQADCggICwABNQAECgYIDAABAAAAAA==.',
Fa='Facestealerr:BAAANQADCgYICAAAAA==.',
Fe='Felgibson:BAAANQADCgYICAAAAA==.',
Fl='Flairrick:BAAANQADCgYIBQAAAA==.Flars:BAAANQAECgEIAQAAAA==.Flatliner:BAAANQAECgcIBwAAAA==.',
Fo='Forq:BAAANQADCgEIAQAAAA==.',
Fr='Frankzappn:BAAANQAECgEIAQAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAAANQAECgEIAQAAAA==.Fruitcakes:BAAANQAECgEIAQAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAQAAAA==.Fuddrael:BAAANQAECgEIAQAAAA==.',
Ga='Gaddess:BAAANQADCgcIDQAAAA==.Ganymede:BAAANQADCgIIAgAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAAANQAECgUIBQAAAA==.',
Gl='Glimagi:BAAANQADCgYIBgAAAA==.',
Gr='Grimjawz:BAAANQAECgQIBQAAAA==.Grippysocks:BAAANQAFFAEIAQAAAA==.',
Gu='Gummibear:BAAANQADCgUICQAAAA==.',
Ha='Haniku:BAAANQADCgUIBQAAAA==.Harthoon:BAAANQAECgYICgAAAA==.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Holiebelle:BAAANQADCgYIBQAAAA==.Holyshield:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Honeynoats:BAAANQADCgcIDQAAAA==.Hotdwarf:BAAANQADCgYIBgAAAA==.',
Hr='Hrumm:BAAANQAECgQIBAAAAA==.',
Hu='Hullkk:BAAANQAECgYIBgAAAA==.Hutchadina:BAAANQADCgIIAgAAAA==.Hutchkins:BAAANQAECgEIAQAAAA==.',
Ic='Icirus:BAAANQAECgQIBAAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAAANQADCgYIBwAAAA==.',
Ja='Jagere:BAAANQADCggIDwAAAA==.Jahde:BAAANQADCgUICQAAAA==.Jandrae:BAAANQAECgQIBQAAAA==.Jassykins:BAAANQADCgYIAwAAAA==.',
Je='Jessecuster:BAAANQADCgMIAwAAAA==.',
Ji='Jiffypop:BAAANQADCgMIAwAAAA==.Jirachii:BAAANQADCgQIBAAAAA==.',
Jo='Joloc:BAAANQADCggIDgAAAA==.',
Ju='Jueles:BAAANQABCgIIAgABNQADCgUICQABAAAAAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Kare:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Karee:BAAANQAECgQIBQAAAA==.',
Ke='Kermodk:BAAANQAECgEIAQAAAA==.',
Kh='Khold:BAAANQADCgYICwAAAA==.',
Ko='Koltara:BAAANQAECgcIDQAAAA==.Koltaros:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.Konshis:BAAANQAECgMIAwAAAA==.Kookymonster:BAAANQAECgIIAgAAAA==.Kos:BAAANQAECgcIDAAAAA==.',
Kr='Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCgUIBQAAAA==.',
Ku='Kuragaru:BAAANQAECgYICgAAAA==.',
La='Lapis:BAAANQADCgcIBwAAAA==.',
Le='Lester:BAAANQADCggIDgAAAA==.Levina:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Li='Lidrahl:BAAANQAECgMIAwAAAA==.Liliria:BAAANQAECgQIBQAAAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAAANQADCgYIBwAAAA==.',
Ln='Lnpoop:BAAANQAECgEIAQAAAA==.',
Lo='Lockjauz:BAAANQABCgQIBAAAAA==.Lorelei:BAAANQADCgcIBwAAAA==.',
Lu='Luc:BAAANQAECgQIBQAAAA==.Lucariõ:BAAANQAECgcICwAAAA==.Lumina:BAAANQADCgYIBQAAAA==.',
Ly='Lyllies:BAAANQAECgQIBQAAAA==.Lyv:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Ma='Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAAANQADCgcIDQAAAA==.Matcauthon:BAAANQADCgYICAAAAA==.Matrim:BAAANQADCgUIBQAAAA==.',
Me='Meekogaia:BAAANQAECgMIBQAAAA==.',
Mi='Mijime:BAAANQADCgYIBgAAAA==.Millerowntoo:BAAANQAECgIIAgAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.',
Mo='Mobius:BAAANQADCgcIDQAAAA==.Molvnma:BAAANQADCgIIAgAAAA==.Montkriege:BAAANQADCgcIDgAAAA==.',
Mu='Murfie:BAAANQAECgEIAQAAAA==.Murica:BAAANQADCgYICgABNQAECgQIBQABAAAAAA==.',
Na='Nashness:BAAANQAECgQIBQAAAA==.',
Ni='Niis:BAAANQAECgEIAQAAAA==.Niterage:BAAANQADCgUIBgAAAA==.',
Nn='Nn:BAAANQADCgYIBQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQABCgEIAQAAAA==.',
['Nè']='Nègan:BAAANQAECgEIAQAAAA==.',
Op='Opuntia:BAAANQADCgYICAAAAA==.',
Pa='Paladinheal:BAAANQADCgYICQAAAA==.Pallypaladin:BAAANQAECgcICgAAAA==.Partywolf:BAAANQADCgYICwAAAA==.',
Ph='Phatzero:BAAANQAECgIIAgAAAA==.',
Po='Polard:BAAANQAECgEIAQAAAA==.',
Pr='Procreeper:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.',
Ra='Rabit:BAAANQADCgEIAQAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rastputin:BAAANQADCggIDAAAAA==.Rawrshåk:BAAANQAECgEIAQAAAA==.',
Rh='Rhodraco:BAAANQADCgYIAgAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAAANQADCggICQABNQADCggICQABAAAAAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Ry='Ryyukken:BAAANQADCgYIDAAAAA==.',
Sa='Saella:BAAANQADCgYICAAAAA==.Samesde:BAAANQADCgIIAgAAAA==.Sarentu:BAAANQAECgQIBQAAAA==.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Senile:BAAANQADCgYIBQAAAA==.',
Sh='Shadyvoid:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Shadówglider:BAAANQADCgYICAAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAAANQAECgEIAQAAAA==.Shamallaman:BAAANQAECgIIAgAAAA==.Sharkweek:BAAANQADCggICwAAAA==.Sheol:BAAANQADCgYIBgAAAA==.Sheyoni:BAAANQADCgUICgAAAA==.Shreck:BAAANQADCgIIAgAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.',
Sk='Skikette:BAAANQADCgcICAAAAA==.Skinrot:BAAANQAECgEIAQAAAA==.',
Sm='Smig:BAAANQADCgUICAAAAA==.',
So='Soeki:BAAANQADCgYIBQAAAA==.Sonyaa:BAAANQADCgYICAAAAA==.Soullove:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.Soullovez:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Soulshocks:BAAANQAECgEIAQAAAA==.Soulviver:BAAANQAECgEIAQAAAA==.',
Sp='Spiritwarden:BAAANQAECgEIAQAAAA==.',
St='Stimer:BAAANQAECgQIBQAAAA==.Stori:BAAANQADCggICgAAAA==.',
Su='Suxor:BAAANQADCgUIBQAAAA==.',
Sw='Swordboardal:BAAANQAECgYICgAAAA==.',
Sy='Sybius:BAAANQADCggICAAAAA==.Symptom:BAAANQAECgEIAQAAAA==.Syncophat:BAAANQADCgYICwAAAA==.',
Ta='Tad:BAAANQADCgQIBQAAAA==.Taint:BAAANQADCgUIBQAAAA==.Takia:BAAANQADCgUIBwAAAA==.Talanzen:BAAANQADCgcIDQAAAA==.',
Th='Thrakara:BAAANQAECgcIDQAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQADCgYIBQAAAA==.Thundrall:BAAANQADCgYIBQAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAAANQADCggIDwAAAA==.',
To='Torches:BAAANQADCgcIBwAAAA==.',
Tr='Truths:BAAANQAECggICwAAAA==.',
Tx='Txbloodstorm:BAAANQADCgYIBgAAAA==.Txgunny:BAAANQADCgIIAgAAAA==.',
Ty='Tymptriss:BAAANQADCgYICAAAAA==.',
Um='Umbren:BAAANQADCgYICgAAAA==.',
Va='Valartha:BAAANQADCgYICAAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgMIBAAAAA==.Velsea:BAAANQADCgMIBAAAAA==.Velstadt:BAAANQADCggIDgAAAA==.Venhance:BAAANQADCggIEgAAAA==.Venotu:BAAANQAECgIIAgAAAA==.Vermilion:BAAANQADCgYIDgAAAA==.',
Vh='Vholatile:BAAANQAECgEIAQAAAA==.',
Vi='Viviel:BAAANQADCgYIDAAAAQ==.',
Wa='Warlockbot:BAAANQAECgUICAAAAA==.Waterboot:BAAANQADCgMIAwAAAA==.Wattheyneed:BAAANQADCggIDwAAAA==.',
We='Wendi:BAAANQADCgYICAAAAA==.',
Wh='Wholesome:BAAANQADCgYIBgAAAA==.',
Wi='Wildbill:BAAANQADCgYIBwAAAA==.',
Wo='Wombo:BAAANQADCggIDgAAAA==.Woolala:BAAANQAECgQIBQAAAA==.',
Wu='Wut:BAAANQADCgYICgABNQAECgQIBQABAAAAAA==.',
Xa='Xalisto:BAAANQADCgMIAwAAAA==.',
Xl='Xlia:BAAANQADCgcIDAAAAA==.',
Ya='Yazmyn:BAAANQADCgYICwAAAA==.',
Ye='Yerehmi:BAAANQADCgYICQAAAA==.',
Yu='Yuny:BAAANQADCgUIBQAAAA==.',
Za='Zaier:BAAANQAECgQIBQAAAA==.',
Ze='Zeltan:BAAANQAECgMIBQAAAA==.',
Zh='Zhundrenga:BAAANQADCgYICAAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
['År']='Åres:BAAANQADCgEIAQAAAA==.',
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
