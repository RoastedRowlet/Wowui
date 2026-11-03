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

local lookup = {'Unknown-Unknown','Warrior-Fury','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Shaman-Elemental','Shaman-Enhancement','Mage-Arcane','Warrior-Protection','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Destruction','Paladin-Protection','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Druid-Feral','Warlock-Affliction','Mage-Frost','DemonHunter-Vengeance','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aazula:BAAANQAECggIEAAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQAECgQICQABNQAECgUIDgABAAAAAA==.',
Ai='Aiden:BAAANQAECgQIBAAAAA==.Aimis:BAAANQADCgUIBQAAAA==.',
Ak='Akusenshi:BAABNQAECn8UAAICAAcKBA5LEQCQAQACAAcKBA5LEQCQAQAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Alisendra:BAAANQADCgUIBQAAAA==.Altayre:BAAANQAECgIIBAAAAA==.Alynas:BAAANQABCgMIAwAAAA==.Alzith:BAAANQADCgEIAQABNQAECggIHAADAMYTAA==.',
Am='Amandil:BAAANQAECgEIAgAAAA==.',
An='Anderon:BAAANQAECgcIEAAAAA==.Animocity:BAAANQAECgMIBAAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.Apophìs:BAAANQAECgUICQAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAABNQAECn8yAAIEAAkKCQ+iaABiAQAEAAkKCQ+iaABiAQAAAA==.',
As='Asylia:BAACNQAFFH8dAAIFAAgKCA/FBAAFAgAFAAgKCA/FBAAFAgA1AAQKfygAAgUACgquHxkbAAMDAAUACgquHxkbAAMDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Aw='Awenz:BAAANQADCgcIBwAAAA==.',
Az='Azryll:BAAANQAECggICwAAAA==.',
Ba='Babalú:BAABNQAECn8dAAIGAAYKCQoc9gAxAQAGAAYKCQoc9gAxAQAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQAECgYIEAAAAA==.Barcaust:BAABNQAECn8cAAIHAAcKKQrmoQACAQAHAAcKKQrmoQACAQAAAA==.Bawlbuster:BAAANQABCgMIAwAAAA==.',
Be='Beargryllis:BAAANQAECgUIEgAAAA==.Beecrafty:BAAANQAECgYIDAAAAA==.Beldradon:BAAANQAECgEIAQAAAA==.Belgord:BAAANQAECgUICwAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQAECgYIDwAAAA==.Blossims:BAAANQAECgEIAQAAAA==.Bluepetal:BAAANQADCgUIBQAAAA==.',
Bo='Board:BAABNQAECn8sAAIHAAoK0BjDZgBbAgAHAAoK0BjDZgBbAgABNQAFFAUIDgAIANcRAA==.Bobbijoe:BAAANQADCgYIBgAAAA==.Bolf:BAAANQAECgQIDQAAAA==.Boombaaby:BAAANQAECgYICQAAAA==.Bopples:BAABNQAECn8rAAIJAAkKKiS8BACrAwAJAAkKKiS8BACrAwAAAA==.',
Br='Breakthings:BAAANQAECgcIDgAAAA==.Britishchick:BAABNQAECn8ZAAIKAAgKxx4yTwCBAgAKAAgKxx4yTwCBAgAAAA==.Brookenoel:BAAANQAECgEIAQAAAA==.Brunhilian:BAAANQADCggIHwAAAA==.Brünjir:BAAANQADCgcICAAAAA==.',
Bu='Buckmaster:BAAANQAECgEIAQAAAA==.',
Ca='Cadun:BAAANQAECgYIEAAAAA==.Cakeismoist:BAAANQAECgMIAgAAAA==.Calaar:BAAANQAECgMIBwABNQADCgYIBgABAAAAAA==.Calada:BAAANQAECgUIDwAAAA==.Callypso:BAABNQAECn8VAAMFAAcK9g2ccwAlAQAFAAcK9g2ccwAlAQALAAUKmgMrtABvAAAAAA==.Carbion:BAAANQADCggICAAAAA==.Cariono:BAABNQAECn8wAAIMAAoKrhNPEwAzAgAMAAoKrhNPEwAzAgAAAA==.Cassandraa:BAAANQAECggIEgABNQAECggIIwABAAAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgkJGgANAFMaAA==.Cathslock:BAAANQAECgEIAgABNQAECgkJGgANAFMaAA==.Cathsmage:BAABNQAECn8aAAINAAkKUxrgpgA0AgANAAkKUxrgpgA0AgAAAA==.Caylann:BAAANQAECgEIAQAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Ci='Ciserro:BAAANQAECgQIBAABNQAECgcIFQAFAPYNAA==.',
Co='Corbyn:BAAANQAECggIBQAAAA==.Corrynn:BAAANQAECgYIBQAAAA==.',
Cr='Cribbage:BAABNQAECn8WAAMOAAoKSCRnAQBJAwAOAAkKSCRnAQBJAwAHAAcKdxI3iwA2AQAAAA==.Crimsonlight:BAAANQAECgUIBgAAAA==.Crzykanaka:BAAANQAECgEIAQAAAA==.',
Cv='Cvaluenigma:BAABNQAECn80AAIDAAkKnxX1GQDnAQADAAkKnxX1GQDnAQAAAA==.',
Cy='Cynosure:BAAANQAECgcJBwABNQAECgoKFgAPAJULAA==.Cytronsneak:BAAANQADCgYICgAAAA==.',
Da='Daliå:BAAANQAECgEIAQAAAA==.Dalrook:BAAANQAECgIIAwAAAA==.Damare:BAAANQAECgEIAQAAAA==.Danl:BAAANQAECgMICAAAAA==.Darkheaven:BAABNQAECn8xAAIGAAkKwxhjUgD/AQAGAAkKwxhjUgD/AQAAAA==.Darkhunntres:BAAANQADCgIIAgAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQAECgUICwAAAA==.',
De='Deathbot:BAAANQAECgEIAgAAAA==.Deathrazor:BAAANQAECgQICAAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQAECgYICgAAAA==.Denae:BAAANQAECgUIDgAAAA==.Desiinnorre:BAAANQAECgIIBAAAAA==.Devinetoro:BAAANQAECgUICAAAAA==.Devour:BAAANQAECgcICwAAAA==.',
Di='Diag:BAABNQAECn8gAAQQAAkKbw5oCwBxAQAQAAkKbw5oCwBxAQARAAQKdRBrJgCdAAASAAEKfAoJJgAsAAAAAA==.Diamos:BAAANQAECgQICQAAAA==.Dijiaih:BAAANQAECgQICwAAAA==.Divinehunger:BAEANQADCgQIBAABNQAECgoKSAATAE4gAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIIwAJAMchAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQAECgEIAQAAAA==.Dwydeshuse:BAAANQADCgUIEAAAAA==.',
Ea='Ears:BAAANQAECgEIAQAAAA==.',
Eg='Egregore:BAAANQAECgEIAgAAAA==.',
Ei='Einheri:BAABNQAECn8lAAMHAAkKVxX3bACBAQAHAAkKVxX3bACBAQACAAEKMAnANQAvAAAAAA==.',
El='Elalian:BAABNQAECn8hAAIUAAkKshKgLADcAQAUAAkKshKgLADcAQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECn81AAIVAAkKPh61CQDaAgAVAAkKPh61CQDaAgAAAA==.Enoira:BAAANQABCgQICAAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQAECgUIDQAAAA==.',
Er='Erat:BAAANQAECgEIAQAAAA==.Erfing:BAAANQAECgQIDAAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Facè:BAAANQAECgEIAQAAAA==.Faffard:BAAANQAECgUIDwABNQAECgkJMQAWAP0JAA==.Fame:BAAANQADCggIEAABNQAFFAcIHAAJAPwBAA==.Faraway:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Farsighted:BAAANQAECgQIBgAAAA==.',
Fe='Fennerick:BAAANQAECgEIAQAAAA==.Ferio:BAAANQAECgIIBAAAAA==.Feyndra:BAAANQAECgUIDgAAAA==.',
Fi='Fishfire:BAAANQAECgUIEQAAAA==.',
Fu='Fubarsnafu:BAAANQABCgUIBgAAAA==.Funenix:BAAANQAECgMIAwAAAA==.',
Fy='Fystie:BAAANQAECgUIDwABNQAECgkJMQAWAP0JAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.Gastro:BAAANQAECgUIDAAAAA==.',
Ge='Gebra:BAABNQAECn8fAAIKAAkKOgxQbgCcAQAKAAkKOgxQbgCcAQAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQICQAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.Gingerdruid:BAAANQAECgEIAQAAAA==.',
Gl='Glorak:BAAANQAECgcICwAAAA==.',
Go='Gorgophone:BAAANQADCgYIBgAAAA==.',
Gr='Grashen:BAABNQAECn8aAAIFAAcK2R+3LgA2AgAFAAcK2R+3LgA2AgAAAA==.Gravorik:BAABNQAECn8mAAMXAAoKnwmVPAAOAQAXAAkKcwqVPAAOAQAGAAYK6ASdPAG/AAAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIIAgABNQAECgkJFgAKAJ8JAA==.Grogu:BAAANQAECgMICQAAAA==.',
Gs='Gsm:BAABNQAECn8tAAILAAkKmQznTABpAQALAAkKmQznTABpAQAAAA==.',
Gu='Gurlyman:BAAANQAECgMIBwAAAA==.',
Ha='Halyon:BAAANQAECgQICAAAAA==.Hante:BAAANQADCgUIAQAAAA==.',
He='Hellblazer:BAABNQAECn8oAAMEAAoKeQXcuwBVAQAEAAoKeQXcuwBVAQAWAAIK4gFGbABHAAAAAA==.Hemazo:BAAANQAECgEIAQAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECn8bAAIJAAcKxh9VPgBrAgAJAAcKxh9VPgBrAgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hoompukka:BAAANQAECgMIBwAAAA==.Hotspur:BAAANQAECgUIBgABNQAECgYIEAABAAAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Ia='Iaanditos:BAAANQADCggICAAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQANAIERAA==.Ilisselia:BAAANQADCggICAAAAA==.Ilokana:BAAANQAECgQIBQAAAA==.Ilostmybible:BAAANQAECgIIAQAAAA==.',
Im='Imwithhir:BAABNQAECn8WAAIUAAkKXxP3IwAoAgAUAAkKXxP3IwAoAgAAAA==.',
Ir='Ironfist:BAAANQAECgQIBgAAAA==.',
It='Itadori:BAABNQAECn8XAAIYAAoKYgphLwBRAQAYAAoKYgphLwBRAQAAAA==.',
Ja='Jacsace:BAAANQAECgEIAQAAAA==.Jacsknight:BAAANQAECgEIAQAAAA==.Jacspally:BAABNQAECn8UAAIGAAYKGhfoyQCIAQAGAAYKGhfoyQCIAQAAAA==.Janora:BAABNQAECn85AAIZAAkKkSIlBwAXAwAZAAkKkSIlBwAXAwAAAA==.Jarlath:BAAANQAECgEIAQAAAA==.',
Je='Jellexy:BAAANQAECgUIDwAAAA==.',
Jh='Jhazy:BAABNQAECn8UAAILAAgKZCJ8JQDvAgALAAgKZCJ8JQDvAgABNQAFFAgIHgAaAJkUAA==.',
Jo='Jolah:BAABNQAECn8wAAMbAAoKLxzwNgCMAgAbAAoKORnwNgCMAgAcAAUKzRhlDwA1AQAAAA==.',
['Jó']='Jósepha:BAAANQADCgYIBgAAAA==.',
Ka='Kaehlen:BAAANQADCggJCAAAAA==.Kailadres:BAAANQAECgYIDAAAAA==.Kailis:BAABNQAECn8nAAIKAAoKUw5bWwDNAQAKAAoKUw5bWwDNAQAAAA==.Kaisa:BAAANQAECgcIDwAAAA==.Kalanizfour:BAAANQAECggIEgABNQAFFAYIIgAZAIciAA==.Karst:BAAANQAECgYIBgAAAA==.Kayzon:BAACNQAFFH8aAAIKAAgKxBXLAgBEAgAKAAgKxBXLAgBEAgA1AAQKfzYAAgoACgreJEUWAEIDAAoACgreJEUWAEIDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.Kiritto:BAAANQAECgcICAABNQAECgoKFwAYAGIKAA==.',
Kl='Klavine:BAABNQAECn9EAAIdAAoKOx6qEQCcAgAdAAoKOx6qEQCcAgAAAA==.',
Ko='Korben:BAAANQAECggIEAAAAA==.',
Kr='Kragorn:BAABNQAECn8ZAAILAAYKmA9kmwBhAQALAAYKmA9kmwBhAQAAAA==.Kronn:BAAANQADCgYIBgAAAA==.Krzykanaka:BAAANQAECgEIAQAAAA==.',
Ku='Kublakhan:BAABNQAECn8rAAIEAAoKOw/DSQDBAQAEAAoKOw/DSQDBAQAAAA==.Kumaneko:BAAANQADCgQIBAAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQAECgUICQAAAA==.',
La='Lakhi:BAABNQAECn8WAAIFAAgK9hn4RgBGAgAFAAgK9hn4RgBGAgAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFH8ZAAIQAAYK6iZkAAC8AgAQAAYK6iZkAAC8AgA1AAQKfyIAAhAACQrnJmgAAPEDABAACQrnJmgAAPEDAAAA.Lauk:BAAANQAECgEIBAAAAA==.Laureli:BAAANQAECgQIDAAAAA==.',
Le='Leeta:BAAANQAECgYIEAABNQAECggIGQAKAMceAA==.Lemooski:BAABNQAECn8YAAIFAAoKexS1KgBLAgAFAAoKexS1KgBLAgABNQAFFAYIFAAeAFIKAA==.Leorra:BAABNQAECn8fAAIGAAkKAAZh+wAoAQAGAAkKAAZh+wAoAQAAAA==.Letholdus:BAABNQAECn8cAAIdAAYKWhOnVABcAQAdAAYKWhOnVABcAQAAAA==.',
Li='Lightningg:BAABNQAECn8oAAMQAAkKbggdDQBIAQAQAAkKbggdDQBIAQASAAgKTwJHEwD8AAAAAA==.Linara:BAAANQAECgEIAgABNQAECgoKQAAHABQcAA==.',
Lo='Loraemar:BAAANQAECgMIAwAAAA==.Losoz:BAAANQAECgQICAAAAA==.',
Lu='Lucariel:BAABNQAECn8cAAMDAAgKxhN4ZwBzAQADAAcKYhR4ZwBzAQAdAAYKWhEAYwAYAQAAAA==.Lusilsandrus:BAABNQAECn8VAAMIAAcKNg9eLADpAAAIAAcKNg9eLADpAAAbAAEKdALU7QAbAAAAAA==.',
Ma='Maclynn:BAAANQAECgUIBQAAAA==.Maddlib:BAABNQAECn8oAAITAAkKACARFAAMAwATAAkKACARFAAMAwABNQAECgoKFgAOAEgkAA==.Maegwin:BAABNQAECn86AAIFAAoKtBjIIwB0AgAFAAoKtBjIIwB0AgAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgoKOAAEAE8hAA==.Maglani:BAAANQAECgMIBAAAAA==.Magusbilly:BAAANQADCgUIBwAAAA==.Mahoutsukai:BAAANQAECgYIBgAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Malagosa:BAAANQADCggIEAAAAA==.Malarch:BAAANQAECgEIAQAAAA==.Malikabe:BAAANQABCgQIBAAAAA==.Mania:BAACNQAFFH8FAAIdAAQKXhO1FgCKAAAdAAQKXhO1FgCKAAA1AAQKfzEAAx0ACgoWJCUaALoCAB0ACQqPIyUaALoCAAMABwrUFXpSAMkBAAAA.Matcauthon:BAAANQAECgQIDAAAAA==.Matti:BAAANQAECgYIEAAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAFFAEIAQABNQAFFAcIGAAQAHwaAA==.Milastrasza:BAAANQABCgIIAgAAAA==.Mildrik:BAABNQAECn8xAAICAAkKvQ/oCwCIAQACAAkKvQ/oCwCIAQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Minimrsmac:BAAANQADCggICAAAAA==.Miracledk:BAAANQAECggIEAAAAA==.Mirkdrak:BAAANQAECgUIDQABNQAECgoKMwAIAKkGAA==.Mishach:BAAANQAECgUIBgABNQAECgYIDQABAAAAAA==.Misheard:BAABNQAECn89AAMaAAoKvRiTFQA7AgAaAAoK1RaTFQA7AgAUAAkKpBLfJgAOAgAAAA==.Misjudged:BAACNQAFFH8HAAMSAAMK3Q4ACADGAAASAAMK3Q4ACADGAAAQAAEKCAGOEQAnAAA1AAQKfycAAxIACgrKFpMHAC8CABIACArfGJMHAC8CABAABwpZEC0gAFQBAAAA.Missmarsha:BAABNQAECn8nAAIKAAkK9ghGjABWAQAKAAkK9ghGjABWAQAAAA==.Missus:BAAANQADCgQIBAABNQAECggIFAAQAKkRAA==.Mit:BAABNQAECn8tAAMLAAkKuA/HQgCPAQALAAkKuA/HQgCPAQAFAAgKwQcbtQADAQAAAA==.Mizzen:BAABNQAECn8nAAIfAAoKlBhCDgBKAgAfAAoKlBhCDgBKAgABNQAFFAUIDgAIANcRAA==.',
Mo='Moegis:BAAANQAECgEIAQAAAA==.Mohtavius:BAABNQAECn8fAAMOAAkKlgzgFQAqAQAOAAkKlgzgFQAqAQAHAAEKsQQ/FAEvAAAAAA==.Mommydearest:BAABNQAECn8xAAIWAAkK/QkFCAAjAQAWAAkK/QkFCAAjAQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAEANQAECgUIBwAAAA==.Moovinhoofer:BAAANQADCgcIBgAAAA==.Motz:BAAANQAECgMIBgAAAA==.',
Mu='Munkìe:BAAANQAECgIIAwABNQAECgkJLQALAJkMAA==.Muura:BAABNQAECn8yAAMDAAoKcA3AIACoAQADAAkKcA3AIACoAQAdAAQKzwIfkgByAAAAAA==.',
My='Mylitlepwny:BAAANQADCgUIDQAAAA==.Myrik:BAAANQAECgEIAgAAAA==.',
['Må']='Mågè:BAAANQAECgIIAgAAAA==.',
['Mè']='Mèièr:BAAANQADCgUICgAAAA==.',
Na='Namini:BAAANQADCggIEQABNQAECgoKLAAGAFUiAA==.Narcissist:BAAANQABCggIDAAAAA==.Nathyrra:BAABNQAECn8iAAMFAAoKjxKlVQCKAQAFAAoKjxKlVQCKAQALAAQK1QpunwCVAAABNQAECgkJKQAeAKsZAA==.',
Ne='Nekorii:BAAANQAECgUIBQAAAA==.',
Ni='Niteroot:BAAANQAECgUICAAAAA==.',
Oe='Oekabe:BAAANQADCgQIBAAAAA==.',
Ot='Otwin:BAAANQAECgcIEwAAAA==.',
Pa='Pahuum:BAAANQAECgMIBwAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAcIHAAJAPwBAA==.Palleigh:BAAANQAECgUIEgAAAA==.Pamaro:BAAANQAECgYICgAAAA==.Pazuzoo:BAAANQADCggICAAAAA==.',
Pe='Pepperjack:BAAANQAECgYIEAAAAA==.Peril:BAAANQAECgEIAQAAAA==.Persimmon:BAABNQAECn85AAIKAAkKORSgUADsAQAKAAkKORSgUADsAQAAAA==.',
Po='Poondor:BAABNQAECn8dAAIJAAkKSRg7NgAPAgAJAAkKSRg7NgAPAgAAAA==.Portalpotty:BAAANQADCgcIBwAAAA==.',
Pr='Predaturd:BAAANQADCgcIEQAAAA==.Prettydruid:BAABNQAECn8tAAIZAAkKnRnZEQDcAQAZAAkKnRnZEQDcAQAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Qu='Quetzalcotal:BAAANQAECgEIAQABNQAECgkJOQATACEPAA==.',
Ra='Raeinthe:BAABNQAECn8tAAIKAAoKkRilQwCgAgAKAAoKkRilQwCgAgAAAA==.Raistlin:BAAANQAECgIIAgABNQAECggIEQABAAAAAA==.Rakshaman:BAABNQAECn8fAAIFAAYKeA2WqQAeAQAFAAYKeA2WqQAeAQAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Reihino:BAAANQAECgQIBQAAAA==.Resiaus:BAABNQAECn9CAAIRAAoKPxTOEwBxAgARAAoKPxTOEwBxAgAAAA==.Reyliina:BAAANQAECgQICAAAAA==.',
Ri='Riest:BAAANQAECgYIBwAAAA==.Rivalina:BAAANQAECgQICgAAAA==.',
Ro='Rojito:BAAANQAECggIDQAAAA==.',
Ru='Run:BAABNQAECn8VAAMbAAkK1gv+hgCCAQAbAAcKZA7+hgCCAQAIAAcKXgO2SgDtAAABNQAFFAcIHAAJAPwBAA==.',
Ry='Ry:BAABNQAECn8fAAIgAAcKphmqEgDUAQAgAAcKphmqEgDUAQAAAA==.',
Sa='Sachtat:BAABNQAECn8jAAIPAAkKsB2FEAB4AgAPAAkKsB2FEAB4AgAAAA==.Saintfoxtrot:BAEANQAECggIDgAAAA==.Saintfrosty:BAEANQAECgYICwABNQAECggIDgABAAAAAA==.Saintkhal:BAEANQAECgEIAQABNQAECggIDgABAAAAAA==.Saintlux:BAEANQAECggIAQABNQAECggIDgABAAAAAA==.Saintmedicus:BAEANQAECggIBwABNQAECggIDgABAAAAAA==.Salandre:BAAANQABCggIFQAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAABNQAECn8qAAIJAAgK1SLyGQC6AgAJAAgK1SLyGQC6AgAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAABNQAECn85AAIbAAkK+SRqCACOAwAbAAkK+SRqCACOAwAAAA==.',
Sh='Shamanta:BAAANQADCgcIAQAAAA==.Shatterstr:BAAANQAECgUICQAAAA==.Shibaryotaro:BAAANQADCgIIAwAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAABNQAECn85AAITAAkKIQ+8LwBmAQATAAkKIQ+8LwBmAQAAAA==.Shivantice:BAABNQAECn8VAAINAAcKCglDoQA2AQANAAcKCglDoQA2AQAAAA==.Shruggie:BAABNQAECn8dAAIaAAYKmQ2sSQDKAAAaAAYKmQ2sSQDKAAAAAA==.Shìnobu:BAABNQAECn8eAAIaAAkK6woQMgBLAQAaAAkK6woQMgBLAQAAAA==.',
Si='Siphondark:BAABNQAECn8wAAIeAAkK+hlMCgBjAgAeAAkK+hlMCgBjAgAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sk='Skivvies:BAAANQAECggICAAAAA==.',
Sm='Smidgen:BAAANQAECgUIBQAAAA==.Smolnad:BAAANQAECgUIDQAAAA==.',
So='Solarís:BAAANQAECgEIAQAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICwAAAA==.Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stormbilly:BAAANQADCgYICAAAAA==.Straightupg:BAAANQAECggIEwAAAA==.Stratacaster:BAAANQAECgYICgAAAA==.Strawberry:BAAANQADCgMIAwAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Su='Sunnja:BAAANQADCgUIBAAAAA==.',
Sy='Syela:BAABNQAECn8WAAIGAAcKqROojAByAQAGAAcKqROojAByAQABNQAECgoKNAATANUTAA==.Synfyl:BAAANQAECggICAABNQAECgoKPQAhAKkQAA==.Synpathi:BAAANQAECggIBQABNQAECgoKPQAhAKkQAA==.Synsyn:BAABNQAECn89AAQhAAoKqRBbCwBBAQAhAAgKXBJbCwBBAQAEAAYKvgSY/QDQAAAWAAUKoQmzRQCvAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQABCgQIBAAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tanshuo:BAAANQADCgYIBgAAAA==.Targonne:BAAANQAECgEIAQAAAA==.Tatsü:BAAANQAFFAMIAwAAAA==.Taylorshift:BAAANQAECgEIAQABNQAECgoKJgAiADwYAA==.Taytemswift:BAAANQAECgQICAABNQAECgoKJgAiADwYAA==.Taílorswift:BAABNQAECn8mAAIiAAoKPBjfCwAAAgAiAAoKPBjfCwAAAgAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAABNQAECn8sAAMGAAoKVSIgGADpAgAGAAoKVSIgGADpAgAXAAEKPRArVwA1AAAAAA==.Terepal:BAAANQAECgYIDQAAAA==.Teri:BAAANQAECgMIAwAAAA==.',
Th='Theel:BAAANQAECgQIBQAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQAECgQIBgAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Treebilly:BAAANQAECgEIAQAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQAECgUIBQAAAA==.',
Ty='Tydyprincess:BAAANQABCgcICAAAAA==.',
Un='Unplugged:BAAANQABCgMIAwAAAA==.',
Ut='Uttrsdeek:BAABNQAECn8fAAMDAAkKyh3jOgA3AgADAAgKdx3jOgA3AgAdAAYKihw9OQDvAQAAAA==.',
Va='Valdraken:BAAANQAECggICAAAAA==.Valfurian:BAAANQAECgEIAQABNQAECgcIFQAFAPYNAA==.Valkky:BAABNQAECn8gAAQjAAgKdxBeDwAbAQAUAAYKewzuPgBTAQAjAAcKdxBeDwAbAQAaAAEKAABqkQA4AAAAAA==.Valkrie:BAAANQABCgIIAgAAAA==.Valky:BAAANQAECgIIAwABNQAECggIIAAjAHcQAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQICAAAAA==.Vasoline:BAAANQAECgcIAgABNQAECggIBwABAAAAAA==.Vaswislor:BAAANQAECgEIAgAAAA==.Vatz:BAAANQAECgQIBgAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgYIDgAAAA==.Vessna:BAAANQAECgUICwABNQAECgoKMwAIAKkGAA==.Veti:BAABNQAECn8UAAIQAAgKqRHkFgDdAQAQAAgKqRHkFgDdAQAAAA==.',
Vi='Vivîán:BAAANQAECgUIEQAAAA==.',
Vo='Vodic:BAABNQAECn8eAAMVAAoKZw4BHQDrAQAVAAoKZw4BHQDrAQAkAAEK5gk2ngA+AAAAAA==.Voras:BAABNQAECn8rAAIFAAoKyBZBQQBbAgAFAAoKyBZBQQBbAgAAAA==.Vorttex:BAAANQADCgYICgAAAA==.',
Wa='Warbilly:BAAANQADCggIDAAAAA==.Wasure:BAAANQAECgYIEAAAAA==.',
Wi='Wildkanaka:BAAANQAECgEIAQAAAA==.',
Wo='Worthy:BAAANQAECgcIEwAAAA==.',
Xe='Xeleik:BAABNQAECn8gAAMdAAoKgxTcNgD8AQAdAAoK1BPcNgD8AQATAAMK0hNkWQC1AAAAAA==.',
Xl='Xlo:BAAANQADCgQIBAAAAA==.',
Xu='Xunay:BAAANQABCggIDAAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Yo='Yoshino:BAABNQAECn8VAAIiAAkKCwjHHAAIAQAiAAkKCwjHHAAIAQABNQAECgEIAwABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAABNQAECn8UAAIfAAoKRhbADwAwAgAfAAoKRhbADwAwAgAAAA==.',
Zi='Ziroquois:BAAANQABCgYICAAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQAECgEIAQAAAA==.Zouk:BAAANQAECgMIBQAAAA==.Zoéy:BAAANQAECgYICQAAAA==.',
Zu='Zube:BAABNQAECn8kAAMbAAoKEx1wIgDkAgAbAAoKEx1wIgDkAgAIAAEKsgfEfgAtAAAAAA==.',
Zy='Zyrren:BAAANQADCgYJBgAAAA==.',
['Âu']='Âuranna:BAAANQADCgQIBAAAAA==.',
['Êx']='Êxecutie:BAAANQAECgIIAgAAAA==.',
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
