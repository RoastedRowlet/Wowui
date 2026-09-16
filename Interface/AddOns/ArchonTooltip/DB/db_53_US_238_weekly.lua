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

local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Restoration','Evoker-Devastation','Mage-Arcane','Druid-Balance','Paladin-Holy','Monk-Windwalker',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aayrawn:BAAANQAECgQIBQAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAAAAA==.Aceshaman:BAAANQAECgYICgAAAA==.',
Ai='Airone:BAAANQADCgYICgAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgUICgABAAAAAA==.',
Am='Amaranthe:BAAANQADCggIDAAAAA==.Amrax:BAAANQAECgQIBAAAAA==.',
Aq='Aquabat:BAAANQAECggIEwAAAA==.',
As='Ashbringer:BAAANQAECggIEAAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAAANQAECgIIAwAAAA==.',
Ba='Baladoria:BAAANQAECgYIDgAAAA==.Baldkrank:BAAANQAECgQIBAAAAA==.Bananabowman:BAAANQAECgIIAgAAAA==.Banditos:BAAANQADCgYICgAAAA==.Bartab:BAAANQAECgIIAwABNQADCggIFAABAAAAAA==.',
Be='Bearemy:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Beastling:BAAANQAECgEIAQAAAA==.Beau:BAABNQAECoEgAAICAAkJ0SFrBQBRAwACAAkJ0SFrBQBRAwAAAA==.Beauwi:BAAANQADCgcIDwABNQAECgkJIAACANEhAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.',
Bo='Bombur:BAAANQAECgMIAwAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.',
Br='Brokenbubble:BAAANQADCgcIBwABNQAECgcIEwABAAAAAA==.Brozown:BAAANQADCgQIBAABNQAECggIEwABAAAAAA==.Brëtski:BAAANQADCggICAAAAA==.',
Bu='Buzzkill:BAAANQADCggIGwAAAA==.',
Ca='Calinash:BAAANQAECgYIBwAAAA==.Calzraxx:BAAANQAECgQICgAAAA==.Cartons:BAAANQADCgQIBAABNQAECgcIBwABAAAAAA==.',
Cc='Ccaan:BAAANQAECgIIAgAAAA==.',
Ce='Celinn:BAAANQAECgYICgAAAA==.',
Ch='Charliek:BAAANQAECgQIBAAAAA==.Chimalma:BAAANQAECgYICgAAAA==.Chorr:BAAANQABCgMIAwABNQAECgUIBQABAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECgcIBwABAAAAAA==.',
Cr='Crates:BAAANQAECgcIBwAAAA==.Cringely:BAAANQAECgYICgAAAA==.Croakam:BAAANQADCgIIAgABNQAECggIEgABAAAAAA==.Crosswalkk:BAAANQADCgUIBQAAAA==.Cryface:BAAANQADCgIIAgABNQABCgQIBAABAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Da='Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEIAQAAAA==.Darkozygo:BAAANQADCggIGQAAAA==.',
De='Deathfortres:BAAANQAECgQIBAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAAANQAECggIEwAAAA==.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAAANQAECggIDQAAAA==.Devit:BAAANQAECgMIBAAAAA==.',
Di='Dimka:BAAANQADCggIDwAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAAANQAECgIIAwAAAA==.',
Do='Donvald:BAAANQAECgEIAQAAAA==.Doodaad:BAAANQADCgYICgAAAA==.Doublerack:BAAANQAECgQIBwABNQABCgQIBAABAAAAAA==.',
Dr='Dragondznuts:BAAANQAECgcIEwAAAA==.Druzizzle:BAAANQADCgQIBAAAAA==.',
Ei='Eilerra:BAAANQAECgIIAwAAAA==.',
Er='Erre:BAAANQAECgYICgAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Firesson:BAAANQADCgIIAgAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQADCgYICQAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.',
Fr='Fritark:BAAANQAECgYICgAAAA==.',
Ge='Gena:BAAANQADCgYIEQAAAA==.Geörge:BAABNQAECoEgAAIDAAkJ1x3eBgAuAwADAAkJ1x3eBgAuAwAAAA==.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAAANQAECgMIAwAAAA==.',
Gr='Gremfrost:BAAANQAECgYIDQAAAA==.Grotelek:BAAANQAECgYICgAAAA==.Grumpywaltz:BAAANQAECgQIBQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.',
Ha='Haedrath:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAAANQAECgYIDwAAAA==.Halleko:BAAANQAECgYIAQABNQAECgkJHQAEAMwhAA==.Hammerfoot:BAAANQAECgIIAgAAAA==.Harkknight:BAAANQAECgIIBAAAAA==.Haurtrue:BAAANQAECgMIBQAAAA==.Hawgbawl:BAAANQAECgQIBgAAAA==.Hawgdream:BAAANQAECgQIBQAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAABNQAECoEdAAMEAAkJzCENBAA3AwAEAAkJzR8NBAA3AwAFAAYJ2R+XEwD8AQAAAA==.Heyyitzrichh:BAAANQAECgcIEAAAAA==.',
Ho='Hollinar:BAAANQAECgUICgAAAA==.Holycøw:BAAANQADCgQIBQAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ih='Ihavecookies:BAAANQADCgYIDwAAAA==.',
In='Invaled:BAAANQAECgQIBwAAAA==.',
Ir='Irateknight:BAAANQADCgYICwAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAECggIGwAGAOEiAA==.Jasmirangel:BAAANQAECgcIEAAAAA==.',
Je='Jenesis:BAAANQAECgYIBgAAAA==.Jermajesty:BAAANQAECgQIBAAAAA==.Jezus:BAAANQABCgYIDQAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQADCgYIBgABNQADCggIEgABAAAAAA==.',
Ka='Kalzifer:BAAANQAECgQICAABNQAECgkJGAAHACYcAA==.Kankaladin:BAABNQAECoEbAAIGAAgJ4SIuEQAYAwAGAAgJ4SIuEQAYAwAAAA==.Kanky:BAAANQAECgUIBQABNQAECggIGwAGAOEiAA==.Kano:BAABNQAECoEZAAMIAAgJUw4dIQCNAQAJAAYJBhFqVQCkAQAIAAgJogUdIQCNAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kawada:BAAANQAECgIIAgAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAAANQAECgQIBQAAAA==.Kennëdi:BAAANQAECgIIAgAAAA==.',
Kh='Khory:BAAANQAECgUIBQAAAA==.',
Ki='Kichirõ:BAAANQAECgYICwAAAA==.',
Km='Kmt:BAAANQADCggIDgAAAA==.',
Ko='Koffee:BAAANQAECgQIBAABNQAECggIGwAGAOEiAA==.Korgigor:BAAANQADCgEIAQAAAA==.',
Kt='Kt:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgYIEgABAAAAAA==.',
La='Ladezar:BAAANQADCgYIBgAAAA==.Laissen:BAAANQADCgYIEgAAAA==.Lattemocha:BAAANQAECgIIBAAAAA==.',
Le='Leprechaun:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Leprechauñ:BAAANQAECgQICgAAAA==.Leprecháun:BAAANQAECgIIAwABNQAECgQICgABAAAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAECggIEwABAAAAAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBgAAAA==.Lishalle:BAAANQADCgUIBQAAAA==.',
Lo='Loutone:BAAANQADCgcICQAAAA==.',
Lu='Ludlow:BAAANQAECgEIAQAAAA==.Lunatonne:BAAANQAECgMIBAAAAA==.Luneztoprime:BAAANQAECgQIBAAAAA==.Luvlybella:BAAANQADCggICAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgIIAgAAAA==.Mallypally:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.Matt:BAABNQAECoEeAAIKAAgJNR/WBwDLAgAKAAgJNR/WBwDLAgAAAA==.Matte:BAAANQAECgcICwABNQAECggIHgAKADUfAA==.Mazza:BAAANQAECgIIAgAAAA==.',
Me='Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECgQIBQAAAA==.',
Mi='Miedillø:BAAANQADCgYIBgABNQAFFAUIDQAJAAoUAA==.Mikeoxmall:BAABNQAECoEZAAMJAAgJnxXFOAAVAgAJAAcJmBjFOAAVAgAIAAUJxwvpKgAUAQAAAA==.',
Mo='Monstermime:BAAANQAECgQIBQAAAA==.Moosetrax:BAAANQAECgYICgAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECgQIBQABAAAAAA==.',
My='Myserie:BAAANQAECgYIDgAAAA==.',
Na='Natsuu:BAAANQABCgIIAgAAAA==.Nazara:BAABNQAECoEcAAILAAkJ9hYXBwC5AgALAAkJ9hYXBwC5AgABNQAECgUIBQABAAAAAA==.',
Ne='Neuro:BAABNQAECoEaAAIMAAcJDRjfaQAJAgAMAAcJDRjfaQAJAgAAAA==.',
Ni='Nikodemos:BAAANQAFFAIIBAAAAQ==.',
Nk='Nkáujhmóob:BAAANQADCgIIAgAAAA==.',
Oo='Oopsifer:BAAANQAECgQIBgAAAA==.',
Op='Optimum:BAAANQADCgQICwAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIIAgAAAA==.',
Pi='Piecemaker:BAABNQAECoEdAAIJAAkJqRvvDQAMAwAJAAkJqRvvDQAMAwAAAA==.',
Pl='Plaguepapi:BAAANQADCgIIAgAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgQIBAAAAA==.',
Py='Pyrrah:BAAANQAECgYICgAAAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAAANQAECgYIEgAAAA==.',
Ra='Rabuf:BAAANQAECgIIBAAAAA==.Radha:BAAANQAECgYIBwABNQAECgkJHgANAF4dAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redizle:BAAANQADCggICAABNQAFFAMIBQAOAAMTAA==.Reginrune:BAAANQAECgUIBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQADCggIEwAAAA==.',
Ri='Ridizle:BAACNQAFFIEFAAIOAAMJAxMFBgALAQAOAAMJAxMFBgALAQA1AAQKgSQAAg4ACQmxH+MGAE4DAA4ACQmxH+MGAE4DAAAA.',
Ro='Rohdoog:BAAANQAECgQICAAAAA==.',
Ru='Runedyu:BAAANQAECgQIDQAAAA==.',
Ry='Ryanno:BAAANQAECggIAgAAAA==.Ryannoo:BAAANQADCgYIBwAAAA==.',
Sa='Sahomi:BAAANQAECgcIDgAAAA==.Sammage:BAAANQADCgEIAQAAAA==.Sarcini:BAAANQAECgQIBgAAAA==.Sarcisse:BAAANQAECgUIBgAAAA==.Satrina:BAAANQAECggIDQAAAA==.Savvy:BAAANQAECgQIBQAAAA==.',
Se='Senaren:BAAANQADCgYIBwAAAA==.Senlain:BAAANQADCgQIBAAAAA==.Seraphiña:BAAANQAECgEIAQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAABAAAAAA==.Shamander:BAAANQADCggIEgAAAA==.Shameonyou:BAAANQAECgMIBAAAAA==.',
Si='Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgMIBAAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAAANQAECgcIDQAAAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAAANQAECgQICAAAAA==.',
Su='Sugars:BAAANQAECgEIAQAAAA==.',
Ta='Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAAANQAECggIEgAAAA==.',
Te='Teostra:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.',
Th='Thedarkduke:BAAANQAECgQIBAAAAA==.Thedarkkness:BAAANQADCgYIBgAAAA==.Thorin:BAAANQAECgUIBwAAAA==.Thud:BAAANQAECgcICAAAAA==.',
Ti='Tidalwave:BAAANQAECgYICgAAAA==.Timmeh:BAAANQADCggIFwAAAA==.Tindra:BAAANQAECgMIBAAAAA==.Tissue:BAAANQAECgYIBgAAAA==.Titanius:BAAANQADCgQIBAABNQAECgUIBQABAAAAAA==.',
To='Tobibi:BAAANQAECgQIBwABNQAECgUIBwABAAAAAA==.Tolip:BAAANQAECgMIBQAAAA==.Tolipally:BAAANQADCgYICwABNQAECgMIBQABAAAAAA==.Tolipicious:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Tollock:BAAANQADCgYIBgAAAA==.Torpse:BAAANQAECgUIBQABNQAECgkJIAANAC0kAA==.',
Tr='Trevórg:BAAANQAECgUICQAAAA==.',
Ts='Tsarrubus:BAAANQAECgYICgAAAA==.',
Tu='Tusck:BAAANQADCgcIDwAAAA==.',
Ul='Ulg:BAAANQAECgYIEAAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQADCggIDAAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAAANQAECgYICgAAAA==.',
We='Wellerman:BAAANQAECgEIAQAAAA==.',
Wi='Wino:BAAANQADCggIGwAAAA==.Wiqui:BAAANQAECgIIAgAAAA==.',
Wo='Wolfonk:BAABNQAECoEaAAIPAAgJygacGgCHAQAPAAgJygacGgCHAQAAAA==.',
Wu='Wuhshake:BAAANQAECgQIBwAAAA==.',
['Wë']='Wërrcs:BAAANQADCgQIBAAAAA==.',
Xe='Xemo:BAAANQAECgQICgAAAA==.Xenophics:BAABNQAECoEZAAIGAAkJyByaGADcAgAGAAkJyByaGADcAgAAAA==.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIBwAAAA==.Zall:BAAANQAFFAEIAQAAAA==.Zamos:BAAANQAECgEIAgAAAA==.',
Ze='Zenshin:BAAANQADCgYIDAAAAA==.Zentaur:BAAANQAECgQIBQAAAA==.',
Zi='Zitfrlt:BAAANQAECgQICAABNQAECgkJGAAHACYcAA==.',
Zo='Zontar:BAAANQAECgQIBQAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
['Ål']='Ålucard:BAAANQAECgIIBAAAAA==.',
['ße']='ßeta:BAAANQAECggIBgABNQAECggIEwABAAAAAA==.',
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
