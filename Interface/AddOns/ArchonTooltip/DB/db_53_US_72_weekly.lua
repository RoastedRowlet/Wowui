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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','Warrior-Arms','Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Retribution','Warrior-Fury','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Druid-Guardian','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','DeathKnight-Frost','Evoker-Devastation','Monk-Mistweaver','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Restoration','Warlock-Affliction','Mage-Frost','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aazula:BAAANQAECggIEAAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQADCgcJCwABNQAECgUICQABAAAAAA==.',
Ak='Akusenshi:BAAANQAECgYICwAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Altayre:BAAANQAECgIIAwAAAA==.Alynas:BAAANQABCgMIAwAAAA==.Alzith:BAAANQADCgEIAQABNQAECgUIEQABAAAAAA==.',
Am='Amandil:BAAANQABCgQIBAAAAA==.',
An='Anderon:BAAANQAECgUIDQAAAA==.Animocity:BAAANQAECgIIAgAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAABNQAECn8hAAICAAcK/Q8qnwCTAQACAAcK/Q8qnwCTAQAAAA==.',
As='Asylia:BAACNQAFFH8UAAIDAAYKDhKyCADCAQADAAYKDhKyCADCAQA1AAQKfxwAAgMACQphIKYaAAMDAAMACQphIKYaAAMDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQAECgYICwAAAA==.',
Ba='Babalú:BAAANQAECgUIEAAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQADCggIJwAAAA==.Barcaust:BAAANQAECgUIDAAAAA==.',
Be='Beargryllis:BAAANQAECgUIDwAAAA==.Beecrafty:BAAANQADCggIIAAAAA==.Belgord:BAAANQAECgQIBAAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQAECgMIBAAAAA==.Blossims:BAAANQAECgEIAQAAAA==.',
Bo='Board:BAABNQAECn8bAAIEAAgK6RhCZQBcAgAEAAgK6RhCZQBcAgABNQAFFAMIBgAFAOsLAA==.Bolf:BAAANQAECgIIBAAAAA==.Boombaaby:BAAANQAECgUIBwAAAA==.Bopples:BAABNQAECn8rAAIGAAkKKiShBACrAwAGAAkKKiShBACrAwAAAA==.',
Br='Breakthings:BAAANQAECgYICwAAAA==.Britishchick:BAABNQAECn8WAAIHAAcKDB/pTQCCAgAHAAcKDB/pTQCCAgAAAA==.Brunhilian:BAAANQADCgUIFgAAAA==.Brünjir:BAAANQADCgcICAAAAA==.',
Ca='Cadun:BAAANQAECgEIAQAAAA==.Cakeismoist:BAAANQAECgIIAgAAAA==.Calada:BAAANQAECgQIBgAAAA==.Callypso:BAAANQAECgYIBgAAAA==.Carbion:BAAANQADCggJCAAAAA==.Cariono:BAABNQAECn8sAAIIAAgKvBYfEwAzAgAIAAgKvBYfEwAzAgAAAA==.Cassandraa:BAAANQAECggIAwAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgcICgABAAAAAA==.Cathslock:BAAANQADCgYIBwABNQAECgcICgABAAAAAA==.Cathsmage:BAAANQAECgcICgAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Co='Corbyn:BAAANQAECggIAwAAAA==.Corrynn:BAAANQAECgUJBQAAAA==.',
Cr='Cribbage:BAAANQADCgYIBgABNQAECgkJKAAJAAAgAA==.Crimsonlight:BAAANQAECgUIBgAAAA==.',
Cv='Cvaluenigma:BAABNQAECn8eAAIKAAgKeBUUQgAQAgAKAAgKeBUUQgAQAgAAAA==.',
Cy='Cynosure:BAAANQAECgcJBwABNQAECggICgABAAAAAA==.Cytronsneak:BAAANQADCgYICgAAAA==.',
Da='Daliå:BAAANQADCgYICQAAAA==.Dalrook:BAAANQAECgIIAwAAAA==.Darkheaven:BAABNQAECn8dAAILAAgKmxk9YgBvAgALAAgKmxk9YgBvAgAAAA==.Darkhunntres:BAAANQADCgEIAQAAAA==.Darknyss:BAAANQADCggIDwAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQAECgQIBAAAAA==.',
De='Deathbot:BAAANQAECgEIAQAAAA==.Deathrazor:BAAANQAECgQIBQAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQAECgEIAQAAAA==.Denae:BAAANQAECgUICQAAAA==.Desiinnorre:BAAANQAECgEIAQAAAA==.Devinetoro:BAAANQAECgQICAAAAA==.Devour:BAAANQAECgcICwAAAA==.',
Di='Diag:BAAANQAECgUIDgAAAA==.Diamos:BAAANQAECgQJCQAAAA==.Dijiaih:BAAANQAECgQICgAAAA==.Divinehunger:BAEANQADCgQIBAABNQAECggIJQAJADcdAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIIwAGAMchAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQAECgEIAQAAAA==.Dwydeshuse:BAAANQADCgUIEAAAAA==.',
Ea='Ears:BAAANQABCgUIBwAAAA==.',
Ei='Einheri:BAABNQAECn8bAAMEAAgKEhQBmgDXAQAEAAgKEhQBmgDXAQAMAAEKMAn+NAAvAAAAAA==.',
El='Elalian:BAABNQAECn8cAAINAAcKmRUtLADcAQANAAcKmRUtLADcAQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECn8uAAIOAAgKQR+dCQDaAgAOAAgKQR+dCQDaAgAAAA==.Enoira:BAAANQABCgMJBQAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQAECgMIBAAAAA==.',
Er='Erfing:BAAANQAECgQIBAAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Facè:BAAANQAECgEIAQAAAA==.Faffard:BAAANQAECgQIBgABNQAECggIJAAPAOcHAA==.Fame:BAAANQADCggIEAABNQAFFAcIGwAGAPwBAA==.',
Fe='Fennerick:BAAANQAECgEIAQAAAA==.Ferio:BAAANQAECgIIAwAAAA==.Feyndra:BAAANQAECgQIBQAAAA==.',
Fi='Fishfire:BAAANQAECgIIBQAAAA==.',
Fu='Funenix:BAAANQADCggIEAAAAA==.',
Fy='Fystie:BAAANQAECgQIBgABNQAECggIJAAPAOcHAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.Gastro:BAAANQAECgQIAwAAAA==.',
Ge='Gebra:BAAANQAECgUIDQAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQICQAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.',
Gl='Glorak:BAAANQAECgYICQAAAA==.',
Gr='Grashen:BAAANQAECgUIDAAAAA==.Gravorik:BAABNQAECn8ZAAMQAAgKlAfcOwAOAQAQAAcK3wfcOwAOAQALAAUKeQUcOAG/AAAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIJAwABNQAECggIDwABAAAAAA==.Grogu:BAAANQAECgMIBQAAAA==.',
Gs='Gsm:BAABNQAECn8WAAIRAAYKaA1knQBYAQARAAYKaA1knQBYAQAAAA==.',
Ha='Halyon:BAAANQAECgIIAwAAAA==.Hante:BAAANQADCgEIAQAAAA==.',
He='Hellblazer:BAABNQAECn8fAAMCAAgKuAWluQBVAQACAAgKuAWluQBVAQAPAAIK4gG5awBHAAAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECn8bAAIGAAcKxh+pPQBrAgAGAAcKxh+pPQBrAgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hotspur:BAAANQAECgQIBAAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQASAIERAA==.Ilokana:BAAANQAECgMIBAAAAA==.',
Im='Imwithhir:BAABNQAECn8WAAINAAkKXxOfIwAoAgANAAkKXxOfIwAoAgAAAA==.',
Ir='Ironfist:BAAANQAECgIIAgAAAA==.',
It='Itadori:BAAANQAECgQICQAAAA==.',
Ja='Jacsknight:BAAANQAECgEIAQAAAA==.Jacspally:BAAANQAECgUIDAAAAA==.Janora:BAABNQAECn8kAAITAAgKFCIMBwAWAwATAAgKFCIMBwAWAwAAAA==.',
Je='Jellexy:BAAANQAECgQIBgAAAA==.',
Jh='Jhazy:BAABNQAECn8UAAIRAAgKZCL3JADvAgARAAgKZCL3JADvAgABNQAFFAcIHAAUAPYSAA==.',
Jo='Jolah:BAABNQAECn8iAAMVAAkKmRwdNgCMAgAVAAkKTxkdNgCMAgAWAAQKvBpPDwA1AQAAAA==.',
['Jó']='Jósepha:BAAANQADCgYIBgAAAA==.',
Ka='Kaehlen:BAAANQADCggJCAAAAA==.Kailadres:BAAANQAECgQIAwAAAA==.Kailis:BAABNQAECn8bAAIHAAcKQQ7VnADJAQAHAAcKQQ7VnADJAQAAAA==.Kaisa:BAAANQAECgUICAAAAA==.Karst:BAAANQADCggIIQAAAA==.Kayzon:BAACNQAFFH8YAAIHAAcKxRehAgBEAgAHAAcKxRehAgBEAgA1AAQKfyIAAgcACQq0JOoVAEMDAAcACQq0JOoVAEMDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.',
Kl='Klavine:BAABNQAECn8sAAIXAAkKHR1yGADEAgAXAAkKHR1yGADEAgAAAA==.',
Ko='Korben:BAAANQAECgcIDwAAAA==.',
Kr='Kragorn:BAAANQAECgUIDgAAAA==.Kronn:BAAANQADCgYIBgAAAA==.',
Ku='Kublakhan:BAABNQAECn8YAAICAAYKFhOKpQCEAQACAAYKFhOKpQCEAQAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQAECgUICQAAAA==.',
La='Lakhi:BAABNQAECn8WAAIDAAgK9hkRRgBGAgADAAgK9hkRRgBGAgAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFH8ZAAIYAAYK6iZdAAC9AgAYAAYK6iZdAAC9AgA1AAQKfyIAAhgACQrnJmYAAPIDABgACQrnJmYAAPIDAAAA.Lauk:BAAANQAECgEIAgAAAA==.Laureli:BAAANQAECgIIAwAAAA==.',
Le='Leeta:BAAANQAECgEIAQABNQAECgcIFgAHAAwfAA==.Lemooski:BAAANQAECgUICQABNQAFFAUIEgAZAKMLAA==.Leorra:BAABNQAECn8ZAAILAAcKjwXa9wAoAQALAAcKjwXa9wAoAQAAAA==.Letholdus:BAAANQAECgUIEAAAAA==.',
Li='Lightningg:BAABNQAECn8aAAMYAAgKmweVHACAAQAYAAgKmweVHACAAQAaAAgKTwIREwD8AAAAAA==.Linara:BAAANQAECgEIAQABNQAECgcIHAAEAFUWAA==.',
Lo='Losoz:BAAANQAECgQIBAAAAA==.',
Lu='Lucariel:BAAANQAECgUIEQAAAA==.Lusilsandrus:BAAANQAECgUICwAAAA==.',
Ma='Maclynn:BAAANQABCgUIBgAAAA==.Maddlib:BAABNQAECn8oAAIJAAkKACCwEwANAwAJAAkKACCwEwANAwAAAA==.Maegwin:BAABNQAECn8iAAIDAAgKXhU7VwAIAgADAAgKXhU7VwAIAgAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgkJJQACAOMfAA==.Maglani:BAAANQAECgMIAwAAAA==.Magusbilly:BAAANQADCgQIBQAAAA==.Mahoutsukai:BAAANQAECgYIBgAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Malagosa:BAAANQADCggICAAAAA==.Malikabe:BAAANQABCgQIBAAAAA==.Mania:BAABNQAECn8nAAMXAAkK0CGTGQC7AgAXAAgKNiGTGQC7AgAKAAcK1BW+UQDIAQAAAA==.Matcauthon:BAAANQAECgQIBQAAAA==.Matti:BAAANQAECgEIAQAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAFFAEIAgABNQAFFAcIFwAYAHwaAA==.Milastrasza:BAAANQABCgIIAgAAAA==.Mildrik:BAABNQAECn8dAAIMAAgKZBBtDQDdAQAMAAgKZBBtDQDdAQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Minimrsmac:BAAANQADCggICAAAAA==.Miracledk:BAAANQAECggICQAAAA==.Mirkdrak:BAAANQAECgQIBQABNQAECgcIHQAFAPgGAA==.Mishach:BAAANQADCggIDwABNQAECgYIDAABAAAAAA==.Misheard:BAABNQAECn8kAAINAAgKnhR6JgAOAgANAAgKnhR6JgAOAgAAAA==.Misjudged:BAACNQAFFH8HAAMaAAMK3Q7NBwDGAAAaAAMK3Q7NBwDGAAAYAAEKCAFUEQAnAAA1AAQKfyYAAxoACQpxGH8HADACABoACArfGH8HADACABgABgqiEekfAFQBAAAA.Missmarsha:BAAANQAECgUIEgAAAA==.Missus:BAAANQADCgQIBAABNQAECgcIDgABAAAAAA==.Mit:BAABNQAECn8fAAMRAAgKtA4HcADMAQARAAgKtA4HcADMAQADAAYKVgg4swADAQAAAA==.Mizzen:BAAANQAECgcIEQABNQAFFAMIBgAFAOsLAA==.',
Mo='Moegis:BAAANQAECgEIAQAAAA==.Mohtavius:BAAANQAECgUIDgAAAA==.Mommydearest:BAABNQAECn8kAAIPAAgK5wcpGgCaAQAPAAgK5wcpGgCaAQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAEANQAECgIIAgAAAA==.Motz:BAAANQAECgMIBgAAAA==.',
Mu='Munkìe:BAAANQADCgEIAQABNQAECgYIFgARAGgNAA==.Muura:BAABNQAECn8jAAMKAAgKpgxnagBlAQAKAAcKpgxnagBlAQAXAAQKzwINjwByAAAAAA==.',
My='Mylitlepwny:BAAANQADCgUIDQAAAA==.',
['Må']='Mågè:BAAANQAECgEIAQAAAA==.',
['Mè']='Mèièr:BAAANQADCgUICgAAAA==.',
Na='Nabsta:BAAANQADCgQJBQAAAA==.Namini:BAAANQADCggICwABNQAECgUIEgABAAAAAA==.Narcissist:BAAANQABCggIDAAAAA==.Nathyrra:BAAANQAECggIDwABNQAECgcIGwAZAK4ZAA==.',
Ne='Nekorii:BAAANQAECgQIBAAAAA==.',
Ni='Niteroot:BAAANQAECgQIBQAAAA==.',
Oe='Oekabe:BAAANQADCgQIBAAAAA==.',
Ot='Otwin:BAAANQAECgUIBgAAAA==.',
Pa='Pahuum:BAAANQADCggIDAAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAcIGwAGAPwBAA==.Palleigh:BAAANQAECgUICQAAAA==.Pamaro:BAAANQAECgYICgAAAA==.',
Pe='Pepperjack:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Pepélepewpew:BAAANQABCgYIBgAAAA==.Peril:BAAANQABCgYICgAAAA==.Persimmon:BAABNQAECn8kAAIHAAgKoBSHbQA0AgAHAAgKoBSHbQA0AgAAAA==.',
Po='Poondor:BAAANQAECgYIDAAAAA==.Portalpotty:BAAANQADCgcIBwAAAA==.',
Pr='Predaturd:BAAANQADCgcIDAAAAA==.Prettydruid:BAABNQAECn8ZAAITAAcKwhjAFwDtAQATAAcKwhjAFwDtAQAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Ra='Raeinthe:BAABNQAECn8nAAIHAAkK9Rl6QgChAgAHAAkK9Rl6QgChAgAAAA==.Rakshaman:BAAANQAECgUIEwAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Reihino:BAAANQADCgcIBwAAAA==.Resiaus:BAABNQAECn8zAAIbAAkKWRSjEwByAgAbAAkKWRSjEwByAgAAAA==.',
Ri='Riest:BAAANQAECgEIAgAAAA==.Rivalina:BAAANQAECgEIAgAAAA==.',
Ru='Run:BAABNQAECn8VAAMVAAkK1gtvhQCCAQAVAAcKZA5vhQCCAQAFAAcKXgPmSQDtAAABNQAFFAcIGwAGAPwBAA==.',
Ry='Ry:BAABNQAECn8aAAIcAAYK2BpWEgDXAQAcAAYK2BpWEgDXAQAAAA==.',
Sa='Sachtat:BAABNQAECn8aAAIdAAgK5RvYFgCHAgAdAAgK5RvYFgCHAgAAAA==.Saintfoxtrot:BAEANQAECgQIBAAAAA==.Saintfrosty:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.Saintkhal:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.Saintmedicus:BAEANQADCggIDAABNQAECgQIBAABAAAAAA==.Salandre:BAAANQABCggIFQAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAAANQAECgUIEgAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAABNQAECn8kAAIVAAgKrCPcEQA4AwAVAAgKrCPcEQA4AwAAAA==.',
Sh='Shamanta:BAAANQADCgYIAQAAAA==.Shibaryotaro:BAAANQADCgIIAwAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAABNQAECn8kAAIJAAgKFg/dUACvAQAJAAgKFg/dUACvAQAAAA==.Shivantice:BAAANQAECgUIDQAAAA==.Shruggie:BAAANQAECgQICQAAAA==.Shìnobu:BAAANQAECggIEwAAAA==.',
Si='Siphondark:BAABNQAECn8bAAIZAAgK2BhsEwBBAgAZAAgK2BhsEwBBAgAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sk='Skivvies:BAAANQAECggICAAAAA==.',
Sm='Smidgen:BAAANQAECgQIBAAAAA==.Smolnad:BAAANQAECgQIBgAAAA==.',
So='Solarís:BAAANQAECgEIAQAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICwAAAA==.Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stormbilly:BAAANQADCgQIBAAAAA==.Straightupg:BAAANQAECgEIAQAAAA==.Stratacaster:BAAANQAECgEIAQAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Sy='Syela:BAAANQAECgQIBAABNQAECggIKQAJAEIUAA==.Synbiot:BAEANQAECggICQABNQAECgkJJQAeAEQMAA==.Synfyl:BAEANQAECggICAABNQAECgkJJQAeAEQMAA==.Synpathi:BAEANQAECggIBQABNQAECgkJJQAeAEQMAA==.Synsyn:BAEBNQAECn8lAAQeAAkKRAy3EgAbAQAeAAQKaw63EgAbAQACAAYKvgSN+gDQAAAPAAUKVQhTRQCvAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQABCgQIBAAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tanshuo:BAAANQADCgYIBQAAAA==.Tatsü:BAAANQAECggICAAAAA==.Taylorshift:BAAANQAECgEIAQABNQAECgcIFAAfAIkUAA==.Taytemswift:BAAANQAECgQICAABNQAECgcIFAAfAIkUAA==.Taílorswift:BAABNQAECn8UAAIfAAcKiRSvCwAAAgAfAAcKiRSvCwAAAgAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAAANQAECgUIEgAAAA==.Terepal:BAAANQAECgYICgAAAA==.Teri:BAAANQAECgMIAwAAAA==.',
Th='Theel:BAAANQAECgEIAQAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQAECgQIBAAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Treebilly:BAAANQADCggICgAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQABCgQIBQAAAA==.',
Ut='Uttrsdeek:BAABNQAECn8bAAMKAAkKyh1kOgA2AgAKAAgKdx1kOgA2AgAXAAYKihwoOADvAQAAAA==.',
Va='Valfurian:BAAANQADCggICQABNQAECgYIBgABAAAAAA==.Valkky:BAAANQAECgUIDgAAAA==.Valky:BAAANQAECgIIAgABNQAECgUIDgABAAAAAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQICAAAAA==.Vasoline:BAAANQAECgcIAgABNQAECggIAwABAAAAAA==.Vatz:BAAANQADCgYIDAAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgUIDAAAAA==.Vessna:BAAANQAECgQIBgABNQAECgcIHQAFAPgGAA==.Veti:BAAANQAECgcIDgAAAA==.',
Vi='Vivîán:BAAANQAECgQICAAAAA==.',
Vo='Vodic:BAABNQAECn8bAAMOAAgKHQ+wHADrAQAOAAgKHQ+wHADrAQAgAAEK5gmamgA+AAAAAA==.Voras:BAABNQAECn8jAAIDAAkK9Rd1QABcAgADAAkK9Rd1QABcAgAAAA==.Vorttex:BAAANQADCgYICgAAAA==.',
Wa='Warbilly:BAAANQADCggIDAAAAA==.Wasure:BAAANQAECgEIAQAAAA==.',
Wo='Worthy:BAAANQAECgQIBQAAAA==.',
Xe='Xeleik:BAABNQAECn8ZAAIXAAgKqBPVNQD9AQAXAAgKqBPVNQD9AQAAAA==.',
Xu='Xunay:BAAANQABCggIDAAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Yo='Yoshino:BAAANQAECgUIDQABNQAECgEIAQABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAAANQADCgcICgAAAA==.',
Zi='Ziroquois:BAAANQABCgYICAAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQADCgYIBgAAAA==.Zouk:BAAANQADCgcJAgAAAA==.Zoéy:BAAANQAECgUICQAAAA==.',
Zu='Zube:BAABNQAECn8eAAMVAAkKRBzDIQDlAgAVAAkKRBzDIQDlAgAFAAEKsgcVfQAtAAAAAA==.',
Zy='Zyrren:BAAANQADCgYJBgAAAA==.',
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
