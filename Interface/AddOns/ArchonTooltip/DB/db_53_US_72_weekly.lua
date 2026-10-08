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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','Priest-Shadow','Paladin-Holy','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Warrior-Fury','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Destruction','Paladin-Protection','Mage-Arcane','Druid-Guardian','Shaman-Elemental','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','DeathKnight-Frost','Evoker-Devastation','Monk-Mistweaver','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Warlock-Affliction','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aazula:BAAANQAECgcIDQAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQADCgcJCwABNQAECgUICwABAAAAAA==.',
Ak='Akusenshi:BAAANQAECgMIBwAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Altayre:BAAANQAECgIIAgAAAA==.Alynas:BAAANQAECgEIAQAAAA==.Alzith:BAAANQADCgEIAQABNQAECgUIDgABAAAAAA==.',
Am='Amandil:BAAANQAECgEIAgAAAA==.',
An='Anderon:BAAANQAECgQICAAAAA==.Animocity:BAAANQAECgIIBAAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAABNQAECoEbAAICAAcKjw7vigCcAQACAAcKjw7vigCcAQAAAA==.',
As='Asylia:BAACNQAFFIEPAAIDAAYKfxBrBgDZAQADAAYKfxBrBgDZAQA1AAQKgRkAAgMACQphIAkVAAwDAAMACQphIAkVAAwDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQAECgQICQAAAA==.',
Ba='Babalú:BAAANQAECgUIDwAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQAECgEIAQAAAA==.Barcaust:BAAANQAECgQICgAAAA==.',
Be='Beargryllis:BAAANQAECgUICwAAAA==.Beecrafty:BAAANQADCggIIAAAAA==.Belin:BAAANQAECgEIAQAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQADCggIEgAAAA==.',
Bo='Board:BAAANQAECgYIEwABNQAFFAMIBgAEAOsLAA==.Bolf:BAAANQAECgEIAgAAAA==.Boombaaby:BAAANQAECgMIBwAAAA==.Bopples:BAABNQAECoErAAIFAAkKKiR5AwCzAwAFAAkKKiR5AwCzAwAAAA==.',
Br='Breakthings:BAAANQAECgYIDAAAAA==.Britishchick:BAAANQAECgYIDwAAAA==.Brunhilian:BAAANQADCgUIFgAAAA==.',
Ca='Cadun:BAAANQADCggIIQAAAA==.Calada:BAAANQAECgEIAgAAAA==.Callypso:BAAANQADCggIIgAAAA==.Carbion:BAAANQADCggJCAAAAA==.Cariono:BAABNQAECoEkAAIGAAgKWxQoEABLAgAGAAgKWxQoEABLAgAAAA==.Cassandraa:BAAANQAECggIAQAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgMIBgABAAAAAA==.Cathslock:BAAANQADCgYIBwABNQAECgMIBgABAAAAAA==.Cathsmage:BAAANQAECgMIBgAAAA==.Caylann:BAAANQAECgEIAQAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Co='Corbyn:BAAANQAECggIBgAAAA==.Corrynn:BAAANQAECgUJBgAAAA==.',
Cr='Cribbage:BAAANQAECgEIAQABNQAECgkJJQAHAOUeAA==.Crimsonlight:BAAANQAECgUIBgAAAA==.Crzykanaka:BAAANQAECgEIAwAAAA==.',
Cv='Cvaluenigma:BAABNQAECoEWAAIIAAgKzRGqSADNAQAIAAgKzRGqSADNAQAAAA==.',
Cy='Cynosure:BAAANQAECgcJCAAAAA==.Cytronsneak:BAAANQADCgYICgAAAA==.',
Da='Daliå:BAAANQADCgYICQAAAA==.Dalrook:BAAANQAECgIICAAAAA==.Damare:BAAANQAECgEIAQAAAA==.Darkheaven:BAABNQAECoEVAAIJAAgKKRSEbwAjAgAJAAgKKRSEbwAjAgAAAA==.Darkhunntres:BAAANQADCgEIAQAAAA==.Darknyss:BAAANQAECgEIAQAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQAECgEIAgAAAA==.',
De='Deathbot:BAAANQAECgEIAQAAAA==.Deathrazor:BAAANQAECgQIAwAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQAECgEIAQAAAA==.Denae:BAAANQAECgUICwAAAA==.Desiinnorre:BAAANQAECgEIAQAAAA==.Devinetoro:BAAANQAECgQICwAAAA==.Devour:BAAANQAECgcIDgAAAA==.',
Di='Diag:BAAANQAECgUIEAAAAA==.Diamos:BAAANQAECgQJCQAAAA==.Dijiaih:BAAANQAECgQIBgAAAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIHQAFAKgfAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQAECgEIAQAAAA==.Dwydeshuse:BAAANQADCgUJDAAAAA==.',
Ea='Ears:BAAANQAECgEIAgAAAA==.',
Ei='Einheri:BAABNQAECoETAAMKAAYKYxZBowCZAQAKAAYKYxZBowCZAQALAAEKMAkYLwAwAAAAAA==.',
El='Elalian:BAABNQAECoEWAAIMAAcKow1IMACcAQAMAAcKow1IMACcAQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECoEqAAINAAgKvx71CQDKAgANAAgKvx71CQDKAgAAAA==.Enoira:BAAANQABCgMJBQAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQAECgEIAgAAAA==.',
Er='Erfing:BAAANQAECgQIBAAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Facè:BAAANQAECgEIAQAAAA==.Faffard:BAAANQAECgEIAgABNQAECgcIHAAOAKsLAA==.Fame:BAAANQAECgEIAQABNQAFFAcIGwAFAPwBAA==.Farsighted:BAAANQADCgYICAAAAA==.',
Fe='Fennerick:BAAANQAECgIIBAAAAA==.Ferio:BAAANQAECgEIAQAAAA==.Feyndra:BAAANQAECgEIAQAAAA==.',
Fi='Fishfire:BAAANQAECgIIBQAAAA==.',
Fu='Funenix:BAAANQADCgcICAAAAA==.',
Fy='Fystie:BAAANQAECgEIAgABNQAECgcIHAAOAKsLAA==.',
Ga='Galpally:BAAANQAECgQIBQAAAA==.Gastro:BAAANQADCggICAAAAA==.',
Ge='Gebra:BAAANQAECgUICgAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQICgAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.',
Gl='Glorak:BAAANQAECgMIAwAAAA==.',
Gr='Grashen:BAAANQAECgMIBwAAAA==.Gravorik:BAABNQAECoEYAAMPAAcKQAlCOgDwAAAPAAYKxglCOgDwAAAJAAUKfwWtFAHFAAAAAA==.Greefkarga:BAAANQAECgEIAQAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIJAwABNQAECggIDwABAAAAAA==.Grogu:BAAANQAECgIIAwAAAA==.',
Gs='Gsm:BAAANQAECgUIEAAAAA==.',
Gu='Gurlyman:BAAANQAECgEIAgAAAA==.',
Ha='Halyon:BAAANQAECgIIAgAAAA==.Hante:BAAANQADCgEIAQAAAA==.',
He='Hellblazer:BAABNQAECoEfAAMCAAgKnwWNoQBjAQACAAgKnwWNoQBjAQAOAAIKhgL4ZgBHAAAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECoEbAAIFAAcKxh/MNAB1AgAFAAcKxh/MNAB1AgAAAA==.Hoofnstien:BAAANQAECgQIBQAAAA==.Hoompukka:BAAANQADCggIDAAAAA==.Hotspur:BAAANQAECgMIAwAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQAQAE8TAA==.Ilokana:BAAANQAECgMIAwAAAA==.',
Im='Imwithhir:BAABNQAECoEUAAIMAAkKShERHgBDAgAMAAkKShERHgBDAgAAAA==.',
Ir='Ironfist:BAAANQADCggIGgAAAA==.',
It='Itadori:BAAANQAECgMICQAAAA==.',
Ja='Jacsknight:BAAANQADCgEIAQAAAA==.Jacspally:BAAANQAECgUIDAAAAA==.Janhaar:BAAANQAECgEIAQAAAA==.Janora:BAABNQAECoEcAAIRAAgKGiJKBQAfAwARAAgKGiJKBQAfAwAAAA==.',
Je='Jellexy:BAAANQAECgEIAgAAAA==.',
Jh='Jhazy:BAABNQAECoEUAAISAAgKcyHRHQD9AgASAAgKcyHRHQD9AgABNQAFFAcIHAATAKgVAA==.',
Jo='Jolah:BAABNQAECoEeAAMUAAgKOhw1QgA9AgAUAAgKaxk1QgA9AgAVAAQK8hgoDwAjAQAAAA==.',
Ka='Kaehlen:BAAANQADCggJCAAAAA==.Kailadres:BAAANQAECgQIBAAAAA==.Kailis:BAABNQAECoEXAAIWAAcKuwwKiwDDAQAWAAcKuwwKiwDDAQAAAA==.Kaisa:BAAANQAECgUICAAAAA==.Karst:BAAANQADCggIIQAAAA==.Kayzon:BAACNQAFFIEXAAIWAAcKaxeDAQBRAgAWAAcKaxeDAQBRAgA1AAQKgSAAAhYACQq6JGwPAFQDABYACQq6JGwPAFQDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.',
Kl='Klavine:BAABNQAECoEmAAIXAAkKGxz6EQDfAgAXAAkKGxz6EQDfAgAAAA==.',
Ko='Korben:BAAANQAECgcIEwAAAA==.',
Kr='Kragorn:BAAANQAECgUIEAAAAA==.Krazycanaka:BAAANQAECgEIAQAAAA==.Kronn:BAAANQADCgYIBgAAAA==.Krzyhayn:BAAANQAECgEIAQAAAA==.',
Ku='Kublakhan:BAAANQAECgUIEQAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQAECgQIBAAAAA==.',
La='Lakhi:BAAANQAECgYIEQAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFIEUAAIYAAYKhyZMAAC5AgAYAAYKhyZMAAC5AgA1AAQKgSEAAhgACQrRJkEAAPkDABgACQrRJkEAAPkDAAAA.Lauk:BAAANQAECgEIAQAAAA==.Laureli:BAAANQAECgEIAQAAAA==.',
Le='Leeta:BAAANQADCggIIgABNQAECgYIDwABAAAAAA==.Lemooski:BAAANQAECgQIBQABNQAFFAUIDQAZAP0KAA==.Leorra:BAAANQAECgYIEgAAAA==.Letholdus:BAAANQAECgUIEQAAAA==.',
Li='Lightningg:BAAANQAECgcIEgAAAA==.Linara:BAAANQAECgEIAQABNQAECgYIFAAKAOIQAA==.',
Lo='Loraemar:BAAANQADCggIDAAAAA==.Losoz:BAAANQAECgQIBAAAAA==.',
Lu='Lucariel:BAAANQAECgUIDgAAAA==.Lusilsandrus:BAAANQAECgQJCQAAAA==.',
Ma='Maclynn:BAAANQAECgEIAQAAAA==.Maddlib:BAABNQAECoElAAIHAAkK5R7MEgABAwAHAAkK5R7MEgABAwAAAA==.Maegwin:BAABNQAECoEhAAIDAAgK7xTXTAAEAgADAAgK7xTXTAAEAgAAAA==.Magicpie:BAAANQADCgQIBAABNQAECggIHQACAJMhAA==.Maglani:BAAANQADCggIDgAAAA==.Magusbilly:BAAANQADCgQIBAAAAA==.Mahoutsukai:BAAANQAECgYIBgAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Malikabe:BAAANQAECgEIAQAAAA==.Mania:BAABNQAECoElAAMXAAkKVyBjFADIAgAXAAgK+iBjFADIAgAIAAcK3xRhSADPAQAAAA==.Matcauthon:BAAANQAECgQJBQAAAA==.Matti:BAAANQADCggIIQAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgYICgABNQAFFAcIFgAYAHcZAA==.Milastrasza:BAAANQAECgEIAQAAAA==.Mildrik:BAABNQAECoEVAAILAAgKugtFDgCnAQALAAgKugtFDgCnAQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Minimrsmac:BAAANQADCggICAAAAA==.Miracledk:BAAANQAECggIBQAAAA==.Mirkdrak:BAAANQAECgEIAQABNQAECgcIFAAEAB4GAA==.Mishach:BAAANQADCggIDwABNQAECgQIBgABAAAAAA==.Misheard:BAABNQAECoEcAAIMAAgKmhC4JQD4AQAMAAgKmhC4JQD4AQAAAA==.Misjudged:BAACNQAFFIEHAAMaAAMKiw5HBgDLAAAaAAMKiw5HBgDLAAAYAAEKCAGTDwAqAAA1AAQKgSMAAxoACQr1GGwGADgCABoACArAGWwGADgCABgABgq9EgUeAFMBAAAA.Missmarsha:BAAANQAECgUIEAAAAA==.Missus:BAAANQADCgQIBAABNQAECgYIEgABAAAAAA==.Mit:BAABNQAECoEXAAMSAAgKDglabwCiAQASAAgKDglabwCiAQADAAYKVghroQAGAQAAAA==.Mizzen:BAAANQAECgYIEgABNQAFFAMIBgAEAOsLAA==.',
Mo='Moegis:BAAANQADCgYIBwAAAA==.Mohtavius:BAAANQAECgUIDAAAAA==.Mommydearest:BAABNQAECoEcAAIOAAcKqwuZHgBxAQAOAAcKqwuZHgBxAQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAAANQAECgEIAgAAAA==.Motz:BAAANQAECgMIBQAAAA==.',
Mu='Munkìe:BAAANQADCgEIAQABNQAECgUIEAABAAAAAA==.Muura:BAABNQAECoEcAAMIAAgKEwuXYgBgAQAIAAcKZAyXYgBgAQAXAAQKWgIwewBzAAAAAA==.',
My='Mylitlepwny:BAAANQADCgUJCQAAAA==.',
['Må']='Mågè:BAAANQAECgEIAgAAAA==.',
['Mè']='Mèièr:BAAANQADCgUIBQAAAA==.',
Na='Nabsta:BAAANQADCgQJBQAAAA==.Namini:BAAANQADCgMJAwABNQAECgUIEAABAAAAAA==.Narcissist:BAAANQAECgEIAQAAAA==.Nathyrra:BAAANQAECgcIDQABNQAECgcIFAAZADsVAA==.',
Ne='Nekorii:BAAANQAECgQIBQAAAA==.',
Ni='Niteroot:BAAANQAECgMIAwAAAA==.',
Oe='Oekabe:BAAANQAECgEIAwAAAA==.',
Ot='Otwin:BAAANQAECgUICAAAAA==.',
Pa='Pahuum:BAAANQADCggIDAAAAA==.Paimon:BAAANQAECgQIBQABNQAFFAcIGwAFAPwBAA==.Palleigh:BAAANQAECgUIBgAAAA==.Pamaro:BAAANQAECgYICQAAAA==.',
Pe='Pepperjack:BAAANQADCggIIQABNQAECgMIAwABAAAAAA==.Pepélepewpew:BAAANQAECgEIAQAAAA==.Peril:BAAANQABCgYICgAAAA==.Persimmon:BAABNQAECoEcAAIWAAgK6xH8XgAwAgAWAAgK6xH8XgAwAgAAAA==.',
Po='Poondor:BAAANQAECgYICgAAAA==.',
Pr='Predaturd:BAAANQADCgcIDAAAAA==.Prettydruid:BAAANQAECgYIEwAAAA==.',
Qi='Qindere:BAAANQAECgEIAQAAAA==.',
Ra='Raeinthe:BAABNQAECoEkAAIWAAgKmBgSSQBrAgAWAAgKmBgSSQBrAgAAAA==.Rakshaman:BAAANQAECgUIDgAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Reihino:BAAANQADCgcIBwAAAA==.Resiaus:BAABNQAECoEsAAIbAAkK0RLzFABNAgAbAAkK0RLzFABNAgAAAA==.',
Ri='Riest:BAAANQAECgEIAgAAAA==.Rivalina:BAAANQAECgEIAQAAAA==.',
Ru='Run:BAABNQAECoEVAAMUAAkK1gshdACHAQAUAAcKZA4hdACHAQAEAAcKYgOtQgD0AAABNQAFFAcIGwAFAPwBAA==.',
Ry='Ry:BAABNQAECoEWAAIcAAYKbRqNDwDbAQAcAAYKbRqNDwDbAQAAAA==.',
Sa='Sachtat:BAAANQAECgYIEgAAAA==.Saintfoxtrot:BAEANQADCggICwABNQAECgEIAQABAAAAAA==.Saintfrosty:BAEANQAECgEIAQABNQAECgEIAQABAAAAAA==.Saintkhal:BAEANQAECgEIAQAAAA==.Saintmedicus:BAEANQADCgQIBAABNQAECgEIAQABAAAAAA==.Salandre:BAAANQABCggIFQAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAAANQAECgUIEgAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAABNQAECoEcAAIUAAgKQSPtDwAyAwAUAAgKQSPtDwAyAwAAAA==.',
Sh='Shamanta:BAAANQADCgYIAQAAAA==.Shatterstr:BAAANQAECgEIAQAAAA==.Shibaryotaro:BAAANQADCgIIAwAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAABNQAECoEcAAIHAAgKkgvjVgB2AQAHAAgKkgvjVgB2AQAAAA==.Shivantice:BAAANQAECgQICAAAAA==.Shruggie:BAAANQAECgMICAAAAA==.Shìnobu:BAAANQAECgYIEAAAAA==.',
Si='Siphondark:BAAANQAECgcIEwAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sk='Skivvies:BAAANQAECggIBwAAAA==.',
Sm='Smidgen:BAAANQAECgQIBgAAAA==.Smolnad:BAAANQAECgIIAgAAAA==.',
So='Solarís:BAAANQAECgEIAgAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICwAAAA==.Spudsy:BAAANQAECgEIAQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Straightupg:BAAANQAECgEIAQAAAA==.Stratacaster:BAAANQADCggICAAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Sy='Syela:BAAANQAECgIIAgABNQAECggIIgAHAJURAA==.Synbiot:BAEANQAECggICQABNQAECgkJHgAOAEwHAA==.Synfyl:BAEANQAECggICAABNQAECgkJHgAOAEwHAA==.Synpathi:BAEANQAECggIBQABNQAECgkJHgAOAEwHAA==.Synsyn:BAEBNQAECoEeAAQOAAkKTAeDRwCfAAACAAUKyQYQ7gC+AAAOAAUKDQWDRwCfAAAdAAIKFwjNHgBnAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQAECgEIAwAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tanshuo:BAAANQADCgUIBAAAAA==.Tatsü:BAAANQAECggICQAAAA==.Taytemswift:BAAANQAECgQIBAABNQAECgQIDAABAAAAAA==.Taílorswift:BAAANQAECgQIDAAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAAANQAECgUIEAAAAA==.Terepal:BAAANQAECgQIBAAAAA==.Teri:BAAANQAECgMIAwAAAA==.',
Th='Theel:BAAANQAECgEIAQAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQADCggIEQAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Treebilly:BAAANQADCggICgAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQAECgEIAgAAAA==.',
Ut='Uttrsdeek:BAABNQAECoEXAAMIAAkKuhxpMwA6AgAIAAgKrhppMwA6AgAXAAYKIhoLPQCXAQAAAA==.',
Va='Valfurian:BAAANQADCggICAABNQADCggIIgABAAAAAA==.Valkky:BAAANQAECgUIDAAAAA==.Valky:BAAANQAECgIJAgABNQAECgUIDAABAAAAAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQICAAAAA==.Vasoline:BAAANQAECgcIAQABNQAECggIAQABAAAAAA==.Vatz:BAAANQADCgYIBwAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgUIDwAAAA==.Vessna:BAAANQAECgEIAgABNQAECgcIFAAEAB4GAA==.Veti:BAAANQAECgYIEgAAAA==.',
Vi='Vivîán:BAAANQAECgIIAwAAAA==.',
Vo='Vodic:BAABNQAECoEbAAMNAAgKdQ+OGQD7AQANAAgKdQ+OGQD7AQAeAAEK5gmQhABAAAAAAA==.Voras:BAABNQAECoEaAAIDAAkK9BfENQBiAgADAAkK9BfENQBiAgAAAA==.Vorttex:BAAANQAECgEIAQAAAA==.',
Wa='Warbilly:BAAANQADCggIDAAAAA==.Wasure:BAAANQADCggIGgAAAA==.',
Wo='Worthy:BAAANQAECgEIAgAAAA==.',
Xe='Xeleik:BAABNQAECoEXAAIXAAcKlBQ6NwC7AQAXAAcKlBQ6NwC7AQAAAA==.',
Xu='Xunay:BAAANQAECgEIAgAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Ye='Yeross:BAAANQAECgEIAQAAAA==.',
Yo='Yoshino:BAAANQAECgQICQABNQADCgUICwABAAAAAA==.',
Yu='Yukilumi:BAAANQAECgEIAgAAAA==.',
Ze='Zeynah:BAAANQAECgEIAwAAAA==.',
Zi='Ziroquois:BAAANQAECgEIAgAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQAECgEIAgAAAA==.Zouk:BAAANQADCgcJAgAAAA==.Zoéy:BAAANQAECgUIDQAAAA==.',
Zu='Zube:BAABNQAECoEbAAIUAAcKhyFgNAB1AgAUAAcKhyFgNAB1AgAAAA==.',
Zy='Zyrren:BAAANQAECgEIAQAAAA==.',
Zz='Zzed:BAAANQAECgEIAQAAAA==.',
['Âu']='Âuranna:BAAANQADCgQIBAAAAA==.',
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
