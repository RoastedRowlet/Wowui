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

local lookup = {'Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Hunter-BeastMastery','Mage-Arcane','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Protection','Paladin-Retribution','Mage-Frost','Priest-Holy','Druid-Guardian','Shaman-Elemental','Priest-Shadow','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Hunter-Survival','Monk-Mistweaver','Druid-Restoration','Priest-Discipline','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECn88AAQBAAoKTRymBgBeAgABAAkK/RmmBgBeAgACAAEKnR8txgBfAAADAAEKeRwLVQBUAAAAAA==.',
Ab='Abracadaver:BAAANQAECgYICAAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgAEAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECn83AAIFAAkKQB2lIACvAgAFAAkKQB2lIACvAgAAAA==.Aegon:BAAANQADCgcIBwAAAA==.Aenledron:BAAANQAECgEIAQABNQAECggIEQAGAAAAAA==.Aetreyu:BAAANQAECgUIBQAAAA==.Aeturnas:BAABNQAECn9DAAIEAAoKCSQyDgBYAwAEAAoKCSQyDgBYAwAAAA==.',
Af='Afukeenba:BAAANQAECgIIAgAAAA==.',
Ag='Aghori:BAAANQAECgQIAwAAAA==.',
Ai='Aire:BAABNQAECn8UAAMHAAcKvAbqXwD+AAAHAAcK+wXqXwD+AAAIAAQKigX/JgCBAAAAAA==.',
Al='Alanima:BAAANQAECgUIBgAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAABNQAECn8WAAIJAAkKKxIFigBJAQAJAAkKKxIFigBJAQABNQAECgoKNAAKADsaAA==.Alittlegeeky:BAAANQADCgIIAgABNQAECgcIFAALALscAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgYIBwAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAGAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECn9QAAILAAoKgR+9GQDdAgALAAoKgR+9GQDdAgAAAA==.',
An='Andralynn:BAAANQAECgQIAwAAAA==.Aneas:BAAANQADCggICAAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQABCgQIBQAGAAAAAA==.',
Aq='Aquilas:BAAANQAECgYIBgAAAA==.',
Ar='Arassa:BAAANQADCgcIBwAAAA==.Archsparks:BAAANQABCgEIAQAAAA==.Arcstream:BAABNQAECn8kAAIMAAoK5Q1SZQDrAQAMAAoK5Q1SZQDrAQAAAA==.Arctica:BAAANQAECgQICwAAAA==.Arete:BAAANQADCggIEAAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkades:BAAANQAECgYIBgABNQAECgoKJAANAJgPAA==.Arkshade:BAABNQAECn8bAAIOAAYKJwtUUADDAAAOAAYKJwtUUADDAAAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Aspir:BAEANQADCgcIBwABNQAFFAYIEgAPAAUWAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECn88AAIQAAoKYBlWBgCoAgAQAAoKYBlWBgCoAgAAAA==.',
At='Atåvvi:BAAANQADCgQIBAAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAABNQAECn80AAILAAoKIReMXgALAgALAAoKIReMXgALAgAAAA==.',
Ay='Ayano:BAABNQAECn9RAAIMAAoKaCNSGABzAwAMAAoKaCNSGABzAwAAAA==.Ayulur:BAAANQAECgEIAwAAAA==.',
Az='Azraél:BAAANQAECgcIBwAAAA==.Azurefalls:BAABNQAECn80AAIFAAoKRyFkCwBYAwAFAAoKRyFkCwBYAwAAAA==.',
Ba='Badfiremage:BAABNQAECn8nAAMJAAoKURq/RgB+AgAJAAoKURq/RgB+AgAQAAEKVwLGhgAhAAAAAA==.Balthïer:BAABNQAECn89AAIEAAoKNhxFNQCPAgAEAAoKNhxFNQCPAgAAAA==.Bark:BAABNQAECn86AAQRAAoKLCKiGABWAwARAAoK3yGiGABWAwASAAUK0hvAEwBkAQATAAMK5h6QHgAKAQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAABNQAECn8tAAMUAAkKVSb7AwB8AwAUAAkKVSb7AwB8AwAVAAcKUhPA6QAOAQABNQAECgoKPgAFAAYmAA==.Beeb:BAABNQAECn8iAAIIAAkK0COOAQAqAwAIAAkK0COOAQAqAwABNQAECgoKPgAFAAYmAA==.Beefisting:BAAANQADCgIIAgABNQAECgoKPgAFAAYmAA==.Beelzébubba:BAAANQADCgIIAgAAAA==.Beethicc:BAAANQAECggICAABNQAECgoKPgAFAAYmAA==.Beezz:BAABNQAECn8+AAIFAAoKBiaSAwC4AwAFAAoKBiaSAwC4AwAAAA==.Beliara:BAAANQAECgQIAwAAAA==.Belwar:BAAANQAECgQIDgAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECn9DAAMWAAoKGx+3BADZAgAWAAoKGx+3BADZAgAMAAEKAACy4wEhAAAAAA==.Bishopwr:BAABNQAECn8yAAMRAAoKEBPvUgAFAgARAAoKEBPvUgAFAgATAAUKvgFRNgCAAAAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBwAAAA==.Bocay:BAAANQAECgYIBgABNQAECgoKKAAXAOIaAA==.Bohica:BAAANQAECgYIBwAAAA==.',
Br='Branch:BAAANQADCgYIBgABNQAECgkJKAAFAMUTAA==.Brecks:BAAANQAECgcIEwAAAA==.Brem:BAABNQAECn82AAIMAAoKFR3qXADGAgAMAAoKFR3qXADGAgAAAA==.Briara:BAAANQAECgQIBQAAAA==.Broknüs:BAAANQAECgMIBAAAAA==.Broníx:BAAANQAECgQICQAAAA==.Bropeep:BAABNQAECn8xAAMOAAoKEyG7IQDAAgAOAAoKEyG7IQDAAgAPAAIKnQnhmQBgAAAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggICwAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgcIGwAYAAoDAA==.Calyen:BAAANQAECgMIAwABNQAECgYIEwAGAAAAAA==.Carartha:BAABNQAECn83AAIVAAoKsAisqwB4AQAVAAoKsAisqwB4AQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgoKJwAJAFEaAA==.Carrots:BAABNQAECn8YAAILAAcKwQtVxgAlAQALAAcKwQtVxgAlAQAAAA==.Cashmoolah:BAABNQAECn9JAAMVAAoKXhP9aQD8AQAVAAoKXhP9aQD8AQAUAAIKzgH7cQAfAAAAAA==.Catfight:BAABNQAECn8bAAIUAAcKaAlkNgDYAAAUAAcKaAlkNgDYAAAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAACNQAFFH8QAAMZAAcKDRD/CwAdAQAZAAYK/Qz/CwAdAQAKAAEKHAFVMgA0AAA1AAQKf1gAAhkACgozHe8fAHUCABkACgozHe8fAHUCAAAA.Change:BAAANQAECgQIBAAAAA==.Charcoal:BAABNQAECn81AAMQAAoKYhYhCQBoAgAQAAkKtRMhCQBoAgAJAAgKQRVKhADbAQAAAA==.Chasebakes:BAABNQAECn89AAMNAAoKKiKwDQAFAwANAAoKYR+wDQAFAwALAAMK6BttDAGaAAAAAA==.Cheesecake:BAABNQAECn8gAAIQAAgKLQusCwAHAQAQAAgKLQusCwAHAQAAAA==.Choks:BAABNQAECn8gAAISAAcKVgk4GgDnAAASAAcKVgk4GgDnAAAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAABNQAECn8nAAIaAAoKeiEtBwD6AgAaAAoKeiEtBwD6AgABNQAFFAcIGQAbAPAcAA==.',
Ci='Cindiyoohoo:BAABNQAECn9AAAIcAAoKcxzyEgCKAgAcAAoKcxzyEgCKAgAAAA==.Cizmac:BAAANQAECgEIAQAAAA==.',
Cl='Clada:BAAANQADCgUIBQAAAA==.Claus:BAAANQADCggICAABNQAECgoKKwAUAAMXAA==.',
Cm='Cmdrshepard:BAAANQADCgEIAQABNQAECgoKLgAQAKwPAA==.',
Co='Corruptdata:BAAANQADCgMIBgAAAA==.Cownado:BAAANQAECgYIEwAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.Crimzzen:BAAANQADCggICAAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgUIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgYIEQABNQAECgcIFAAHALwGAA==.',
Cy='Cyfelen:BAABNQAECn9FAAQQAAoK0B50AgBWAgAJAAoKZxjSRACEAgAQAAoKtRx0AgBWAgAdAAIKsB28HQCOAAAAAA==.Cynleel:BAAANQAECgYIBwAAAA==.Cyris:BAAANQAECgcIBgAAAA==.',
Da='Dahrena:BAAANQAECgYICwAAAA==.Darthmall:BAAANQAECgYIDwABNQAFFAQICwAYAJQTAA==.Dawgg:BAAANQAECggICQAAAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Deadgeknight:BAAANQAECgQIBAAAAA==.Delyta:BAAANQAECggICwAAAA==.Demidru:BAABNQAECn8mAAIYAAoKoxxREwAuAgAYAAoKoxxREwAuAgAAAA==.Demonicdawn:BAAANQAECgQIBAAAAA==.Derat:BAAANQADCggICAAAAA==.Deucalion:BAAANQADCgcICQAAAA==.Deveruxx:BAAANQADCgUIBQAAAA==.',
Di='Dibbydab:BAAANQAECggIEAAAAA==.',
Dj='Django:BAABNQAECn8eAAIcAAkKkRbvJgCcAgAcAAkKkRbvJgCcAgAAAA==.Djehrtey:BAAANQAECgUIDQAAAA==.Djinni:BAABNQAECn8oAAMeAAkKmh1rBgDnAgAeAAkKmh1rBgDnAgAfAAQKXRFeRQCVAAABNQAFFAQICwAYAJQTAA==.Djwiltumble:BAAANQAECgMIBAAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAABNQAECn8hAAIPAAoKsRY4QQDBAQAPAAoKsRY4QQDBAQAAAA==.',
Dr='Dracnahr:BAAANQAECgcIEgAAAA==.Drenleah:BAABNQAECn8cAAMQAAoKyg+TEwDUAQAQAAgK7Q6TEwDUAQAJAAgKVAwkbwCMAQABNQAECgoKOAAgAEccAA==.Drenlee:BAAANQAECgIIAgABNQAECgoKOAAgAEccAA==.Dromokafrapp:BAAANQAECgIIAgAAAA==.',
Du='Dumblegear:BAABNQAECn8aAAIMAAgKeBryfQCCAgAMAAgKeBryfQCCAgAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAABNQAECn80AAIKAAoKOxq1KQC8AgAKAAoKOxq1KQC8AgAAAA==.',
Dw='Dwagon:BAAANQADCgYIBgABNQAECgoKMwAKAAoSAA==.',
Dy='Dysdayne:BAAANQAECgQIBwAAAA==.',
['Dë']='Dëathx:BAAANQADCgcIBwABNQAECgkJMQASALAVAA==.',
Ed='Edinna:BAABNQAECn8zAAIMAAoK6QnGgACoAQAMAAoK6QnGgACoAQAAAA==.',
Ei='Eileamaid:BAAANQAECgQIBQAAAA==.',
El='Elessedil:BAAANQAECgUIBgAAAA==.Ellemystic:BAAANQAECgQICQAAAA==.Elpally:BAAANQADCgMIAwAAAA==.Elspeth:BAAANQADCggICAABNQAECgcIGwAYAAoDAA==.Elyriana:BAAANQAECgcIDwAAAA==.',
Em='Emila:BAEANQAECgcIDQABNQAECgoKNwALADsiAA==.Emirozu:BAAANQADCgUIBQAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECggIEwAAAA==.Emriq:BAAANQAECgMIBAAAAA==.',
En='Enrique:BAABNQAECn9cAAMVAAoKzyRXIwA3AwAVAAoKzyRXIwA3AwAUAAEK0xP1agA8AAAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECgkJKAAFAMUTAA==.Erusdh:BAAANQAECgMIBQAAAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECggIBgAAAA==.',
Ev='Eveninwillow:BAAANQADCggICAAAAA==.Evöö:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgUIBgAAAA==.',
Fa='Faeng:BAABNQAFFH8LAAIYAAQKlBM7BADGAAAYAAQKlBM7BADGAAAAAA==.Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgcIDQAAAA==.Faubito:BAAANQAECgYIBgAAAA==.',
Fe='Fearlesfreep:BAABNQAECn9KAAILAAoKahZWQQBSAgALAAoKahZWQQBSAgAAAA==.Febz:BAAANQAECgUICAAAAA==.Felatonin:BAABNQAECn8ZAAIgAAgK6B+8GgCCAgAgAAgK6B+8GgCCAgAAAA==.Felfüry:BAABNQAECn9OAAMIAAoKgRO7DgBeAQAHAAoK0hIpLQCqAQAIAAkKjg+7DgBeAQAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQADCgcIDQAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAABNQAECn8kAAMNAAoKmA8JJgA5AQANAAcKMQ0JJgA5AQALAAUKQhH+2gD8AAAAAA==.',
Fo='Fogassann:BAAANQAECgUICgABNQAECgoKQgATAAsiAA==.Foggpy:BAABNQAECn8/AAIdAAoK7iI4AQBWAwAdAAoK7iI4AQBWAwAAAA==.Fogtotem:BAAANQAECgUIBwABNQAECgoKPwAdAO4iAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUIDAAAAA==.Fröstmöurne:BAABNQAECn84AAIFAAkKag2DOgBYAQAFAAkKag2DOgBYAQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.Furydeath:BAAANQAECgIIAgAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQAECgUICAAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgcIGgAJAHUdAA==.Genghiskhan:BAABNQAECn8sAAIOAAkKxRrAKgCLAgAOAAkKxRrAKgCLAgAAAA==.Geren:BAAANQAECggIDwAAAA==.Geret:BAABNQAECn8pAAIVAAgKhRPsjgAHAgAVAAgKhRPsjgAHAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYIEQAAAA==.',
Gl='Glitchy:BAABNQAECn9FAAIcAAoKYRZpHgAOAgAcAAoKYRZpHgAOAgAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECn9FAAIUAAoKqR37DgCtAgAUAAoKqR37DgCtAgAAAA==.Goldfarmr:BAABNQAECn8WAAIXAAoK5xFSUwApAgAXAAoK5xFSUwApAgABNQAECgoKPgAMAIMfAA==.Goldglazeher:BAABNQAECn8+AAIMAAoKgx80OgATAwAMAAoKgx80OgATAwAAAA==.Goldrawr:BAAANQAECgYICgABNQAECgoKPgAMAIMfAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAABNQAECn8qAAINAAoKpB9TDQBmAgANAAoKpB9TDQBmAgAAAA==.Greganir:BAABNQAECn8YAAMWAAgKdxroGwARAQAMAAgKaxaGrQAnAgAWAAQKOhroGwARAQABNQAECgkJGgAFAEsZAA==.Gregdapro:BAABNQAECn8aAAIFAAkKSxmXNwArAgAFAAkKSxmXNwArAgAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAABNQAECn8dAAQTAAYK0gpfKgCsAAATAAYK0gpfKgCsAAARAAUK7gZ5GwGlAAASAAQKKwZ1JwBvAAAAAA==.',
Gy='Gyathew:BAABNQAECn8qAAIZAAkKRyBWEwBXAwAZAAkKRyBWEwBXAwAAAA==.',
Ha='Hagunn:BAABNQAECn8ZAAMRAAkKPxdPgwATAgARAAkKxxRPgwATAgASAAMK9Ru6GgD6AAAAAA==.Happerixie:BAAANQADCgcIBwAAAA==.',
He='Heatfrezze:BAAANQAECggIDAAAAA==.Heladaa:BAAANQADCgMIAwAAAA==.Hervöralvit:BAAANQADCgIIAgAAAA==.Hevy:BAABNQAECn84AAIgAAoKRxyYDgBrAgAgAAoKRxyYDgBrAgAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holygriff:BAAANQAECgIIAgAAAA==.Holyshots:BAABNQAECn9HAAIVAAoK5ROWcwDnAQAVAAoK5ROWcwDnAQAAAA==.Howlinnbrews:BAAANQADCgcICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Id='Idrizzt:BAAANQAECgQIDQAAAA==.',
Ig='Ignore:BAAANQAECggICgABNQAECgoKJwAJAFEaAA==.',
Io='Iobo:BAABNQAECn8hAAIhAAcK9RAcCQBaAQAhAAcK9RAcCQBaAQAAAA==.',
Ir='Ironhidez:BAABNQAECn88AAIVAAoKIwv9nwCOAQAVAAoKIwv9nwCOAQAAAA==.',
Is='Isaarek:BAAANQAECgEIAQAAAA==.Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAABNQAECn8jAAILAAkKIxoddQDVAQALAAkKIxoddQDVAQABNQAECgoKNAAKADsaAA==.',
Iz='Izerol:BAABNQAECn9fAAIfAAoK/STKAgBRAwAfAAoK/STKAgBRAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.Jayabin:BAAANQABCgIIAgAAAA==.Jaylea:BAAANQAECgUIBgAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGgAEAP0dAA==.Jebopally:BAABNQAECn8aAAMEAAgK/R2dPAByAgAEAAcKiB6dPAByAgAVAAcKnhk/qADPAQAAAA==.Jetblack:BAABNQAECn8dAAIJAAcKfxlGfwDoAQAJAAcKfxlGfwDoAQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAABNQAECn9AAAITAAoKSSAFBgCoAgATAAoKSSAFBgCoAgAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAABNQAECn8cAAIRAAgKVhIuhQB7AQARAAgKVhIuhQB7AQAAAA==.',
Ka='Kaidoe:BAAANQAECgYIBwAAAA==.Kaleesh:BAACNQAFFH8RAAIbAAcKsyPhAADIAQAbAAcKsyPhAADIAQA1AAQKfzYAAhsACgpLJn0BAFQDABsACgpLJn0BAFQDAAAA.Kallux:BAABNQAECn9CAAIFAAoKrh8KDgC5AgAFAAoKrh8KDgC5AgAAAA==.Kalma:BAABNQAECn8vAAIFAAoKyx6uFwBJAgAFAAoKyx6uFwBJAgAAAA==.Kananga:BAABNQAECn8cAAIXAAcKWBNEcgCFAQAXAAcKWBNEcgCFAQAAAA==.Kasca:BAABNQAECn8ZAAIcAAcKQAhVYACiAAAcAAcKQAhVYACiAAAAAA==.Kato:BAAANQAECgUICQABNQAECgoKNwAbAI0aAA==.',
Ke='Kerah:BAAANQADCggICAABNQAECgoKNAAKADsaAA==.',
Kh='Khadran:BAAANQADCgIIAwAAAA==.Khalyraa:BAAANQAECgUICQAAAA==.',
Ki='Kiermac:BAABNQAECn8VAAILAAgKuwm5xQAmAQALAAgKuwm5xQAmAQAAAA==.Kindred:BAAANQAECgIIAgAAAA==.Kiragrande:BAABNQAECn8qAAIiAAoKvhGgFQAiAgAiAAoKvhGgFQAiAgAAAA==.Kiriku:BAABNQAECn8XAAIcAAUKhwwPWQC8AAAcAAUKhwwPWQC8AAAAAA==.Kithane:BAAANQADCgMIBgAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgUIBQAAAA==.Kotok:BAABNQAECn8ZAAMKAAgKiAwlkQAEAQAKAAcKsAslkQAEAQAbAAIK1wTqNwAwAAAAAA==.',
Kr='Krelein:BAABNQAECn8iAAIUAAgK4hRgIQBjAQAUAAgK4hRgIQBjAQAAAA==.',
Ku='Kurth:BAAANQAECgQIBAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
['Ká']='Káinan:BAAANQADCgIIAgAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECn8ZAAIfAAcK4yIZGACIAgAfAAcK4yIZGACIAgAAAA==.Leenaashala:BAABNQAECn8ZAAILAAgKQRI0kQCTAQALAAgKQRI0kQCTAQABNQAECgoKNwAbAI0aAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMIBgABNQAFFAQICwAYAJQTAA==.',
Ll='Llght:BAABNQAECn8ZAAMXAAoKfhwIJADFAgAXAAoKfhwIJADFAgAaAAIKqgZSbwBKAAAAAA==.',
Lo='Logankord:BAABNQAECn8+AAISAAoK+SDNAwDGAgASAAoK+SDNAwDGAgAAAA==.Lokeira:BAABNQAECn8zAAIKAAoKChJqXQD3AQAKAAoKChJqXQD3AQAAAA==.Lonki:BAAANQAECgQIAwAAAA==.Lono:BAAANQAECgcICAAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luvbug:BAABNQAECn8UAAILAAcKuxzRagA+AgALAAcKuxzRagA+AgAAAA==.',
Ly='Lyais:BAAANQAECgQICQAAAA==.Lyara:BAACNQAFFH8LAAIKAAcK5xdXCgDGAQAKAAcK5xdXCgDGAQA1AAQKfzcAAwoACgqFHucrALMCAAoACgqFHucrALMCABkACQrAG04hAGwCAAAA.Lythos:BAABNQAECn8oAAIFAAkKxRM3TgC9AQAFAAkKxRM3TgC9AQAAAA==.',
['Lø']='Lørdøfßud:BAABNQAECn9CAAMTAAoKCyJJBADqAgATAAoKCyJJBADqAgARAAEKAAANUAE2AAAAAA==.',
Ma='Machomans:BAAANQAECgQIBQABNQAECgcIEAAGAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Magicmeat:BAAANQAECgQIBgAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Makimá:BAAANQADCgYIBgABNQAECgoKFgACAAILAA==.Mandragora:BAAANQADCgIIAgAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECn9NAAIDAAoKdRIIDQD8AQADAAoKdRIIDQD8AQAAAA==.Mastamojo:BAABNQAECn8fAAIEAAgKwgdiiwB6AQAEAAgKwgdiiwB6AQAAAA==.Mattheals:BAABNQAECn84AAMXAAoKMRkeLQCSAgAXAAoKMRkeLQCSAgAaAAEKAABRfAAAAAAAAA==.',
Mc='Mcfudd:BAAANQAECgQIBgAAAA==.Mcmurphy:BAAANQAECgMIAwAAAA==.',
Me='Meanieman:BAAANQABCggIDAAAAA==.Meanpaula:BAAANQADCgMIAwAAAA==.Meissen:BAABNQAECn8uAAMQAAoKrA/UBQCSAQAQAAkKCBHUBQCSAQAdAAEKKgagMAAuAAAAAA==.Melendaren:BAAANQAECgEIAgAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Meowandi:BAAANQAECgEIAQAAAA==.Messìah:BAABNQAECn8oAAMcAAgK5A34NwBVAQAcAAgK5A34NwBVAQAjAAQKwg1dUQC1AAAAAA==.Metamonster:BAABNQAECn8hAAMOAAoKhAtgLQB+AQAOAAoK+AlgLQB+AQAFAAMKFhGhgQBmAAAAAA==.',
Mi='Mickie:BAABNQAECn8bAAIYAAcKCgPLPQDGAAAYAAcKCgPLPQDGAAAAAA==.Miniav:BAAANQAECgQICgAAAA==.Mirko:BAAANQADCgYJCQABNQAECgcIEAAGAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAABNQAECn9UAAIMAAoK5RDrWgAFAgAMAAoK5RDrWgAFAgAAAA==.Mokokniki:BAABNQAECn8nAAIjAAoK7xKILQCvAQAjAAoK7xKILQCvAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgYIEQAAAA==.Morticiá:BAAANQAECgcIBwAAAA==.Mourningstar:BAACNQAFFH8MAAIOAAYKRRmMBQDLAQAOAAYKRRmMBQDLAQA1AAQKfycAAw4ACgp6I+EUABIDAA4ACAqAI+EUABIDAAUABgr0HrdiAGcBAAE1AAUUBwgWAAUAzxkA.Mozaic:BAABNQAECn9NAAITAAoKUyDlBADTAgATAAoKUyDlBADTAgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQAECgQIDgAAAA==.Naec:BAAANQADCgEIAQABNQAECgQIBwAGAAAAAA==.Naek:BAAANQAECgQIBwAAAA==.Nalthis:BAAANQAECggICQAAAA==.',
Ne='Necromus:BAAANQAECgYIEwAAAA==.Nekra:BAABNQAECn8eAAMcAAgK9AtiPgAxAQAcAAgK9AtiPgAxAQAYAAUKLAb+WABjAAAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcIDAAAAA==.',
No='Nocturnum:BAACNQAFFH8FAAIgAAMKlwq8EQCCAAAgAAMKlwq8EQCCAAA1AAQKf0wAAiAACgrGItIHAFQDACAACgrGItIHAFQDAAAA.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
['Nø']='Nøir:BAAANQAECgIIAgAAAA==.',
Oh='Oha:BAAANQAECgMIAwAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBAABNQAECgQIBwAGAAAAAA==.',
On='Onepuffman:BAACNQAFFH8ZAAIbAAcK8BzxAAA9AgAbAAcK8BzxAAA9AgA1AAQKfz0AAhsACgrpJFMCADoDABsACgrpJFMCADoDAAAA.Onetwocowpow:BAABNQAECn9HAAIiAAoK7BPQDwAaAgAiAAoK7BPQDwAaAgAAAA==.',
Or='Ordanith:BAABNQAECn84AAIVAAoKYiGtIgA5AwAVAAoKYiGtIgA5AwAAAA==.Orionn:BAACNQAFFH8ZAAILAAcKyBsjBADCAQALAAcKyBsjBADCAQA1AAQKf18AAwsACgrcJgIBAJcDAAsACgrcJgIBAJcDAA0AAgr9EjxHAIAAAAAA.',
Os='Osø:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAABNQAECn8xAAQiAAoKwhVJFQAnAgAiAAgKfhZJFQAnAgAfAAkK/A8wKQBPAQAeAAEKDw4qMQA1AAAAAA==.',
Ow='Owlette:BAAANQAECgQIBAAAAA==.Owlxero:BAAANQAECgQIBQAAAA==.',
Pa='Patelz:BAAANQADCgYIBgAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAGAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYIDwAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgYIEQAGAAAAAA==.Problem:BAAANQAECgYIBgAAAA==.',
Ps='Psygon:BAAANQADCgYIBgAAAA==.',
Qu='Quora:BAAANQABCggIEgAAAA==.',
Ra='Raelone:BAABNQAECn8sAAMQAAoKIhfeCQApAQAQAAcKpRfeCQApAQAdAAQKmBU1FgDnAAAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECggIEgAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIDAAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECn89AAILAAoKIxhmSgCOAgALAAoKIxhmSgCOAgAAAA==.Ranoa:BAABNQAECn8UAAIUAAgKqxBzKwCBAQAUAAgKqxBzKwCBAQABNQAECgoKMgAYAN0eAA==.Rant:BAAANQAECgUICwAAAA==.Ravencraw:BAAANQADCgYICgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redishpanda:BAAANQADCgYIBgAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgYIDAAAAA==.Reo:BAAANQADCgQIBAAAAA==.Reverandrott:BAAANQAECgUIBgAAAA==.Reàper:BAAANQAECgEIAQAAAA==.',
Rh='Rheavin:BAAANQABCgQIBQAAAA==.Rhell:BAABNQAECn8bAAIEAAgKRSDoIwDbAgAEAAgKRSDoIwDbAgAAAA==.Rhellen:BAABNQAECn8uAAIXAAoKEB+QGgAJAwAXAAoKEB+QGgAJAwABNQAECggIGwAEAEUgAA==.',
Ri='Rinche:BAABNQAECn8VAAMZAAcK+wfYogBQAQAZAAcK+wfYogBQAQAKAAMKOgcx+AB6AAAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAABNQAECn8WAAINAAgK8hY0JAAsAgANAAgK8hY0JAAsAgAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAACNQAFFH8MAAIJAAQKywoCHQDIAAAJAAQKywoCHQDIAAA1AAQKfycAAgkACgqaEThsABkCAAkACgqaEThsABkCAAAA.',
Ru='Rudo:BAABNQAECn8bAAQNAAkKGxSVOACLAQALAAcKKRYXrQCqAQANAAgKWwqVOACLAQAhAAMK6wdtDwCXAAABNQAECgoKFgACAAILAA==.Rumproblem:BAABNQAECn82AAQXAAoKwxVONwBgAgAXAAkKFhdONwBgAgAaAAgKNgtMJgBSAQAkAAcKwA3CDwAuAQAAAA==.Ruri:BAAANQAECgMIBAABNQAECgoKFgACAAILAA==.',
Ry='Ryegar:BAAANQADCgcIDAABNQAECgoKPwAlABIbAA==.Ryeger:BAABNQAECn8/AAMlAAoKEhv5CQBBAgAlAAoKEhv5CQBBAgAcAAUK0gVmfgDTAAAAAA==.Ryuaoi:BAAANQAECgIIAwABNQABCgQIBQAGAAAAAA==.',
['Ró']='Róótbear:BAAANQAECgUICgAAAA==.',
Sa='Safety:BAAANQAECgUIDwAAAA==.Salaine:BAAANQAECgUIBgAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Salliri:BAAANQAECgQIBAAAAA==.Samovar:BAABNQAECn9DAAMVAAoKQxISfADVAQAVAAoKQxISfADVAQAEAAYKywWowAD7AAAAAA==.Samovaro:BAAANQADCgQIBAAAAA==.Sandbones:BAAANQAECgQICAABNQAECgoKVAAMAOUQAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECn83AAMmAAoKMBycBABaAgAmAAoKMBycBABaAgAnAAUKPhi1EwD6AAAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sensou:BAAANQAECgYIBQABNQAECgoKNwAbAI0aAA==.Sentren:BAAANQAECgUIBwAAAA==.Seo:BAAANQADCgQIBAAAAA==.Setresh:BAABNQAECn88AAIhAAoK9hKwBACRAgAhAAoK9hKwBACRAgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shammatty:BAAANQAECgYIBgAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECgoKPQAEADYcAA==.Sharatira:BAAANQAECgMIBgAAAA==.Shivver:BAAANQADCgQIBAAAAA==.Shivyn:BAABNQAECn9TAAIKAAoKxxgKKgB/AgAKAAoKxxgKKgB/AgAAAA==.Sholan:BAAANQAECgEIAQAAAA==.',
Si='Sibadeekay:BAABNQAECn9KAAMOAAoKGR6NEgBiAgAOAAoK6ByNEgBiAgAFAAUKHCH+UACxAQAAAA==.Sickkid:BAABNQAECn8+AAMSAAoKARNnCgDwAQASAAkKARNnCgDwAQARAAcKxwlhwwB0AQAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgYIDQAAAA==.Sindrya:BAAANQAECgYIDAAAAA==.',
Sk='Skunkt:BAAANQADCgMIAwAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAABNQAECn83AAIbAAoKjRpuDABQAgAbAAoKjRpuDABQAgAAAA==.',
Sn='Snooker:BAAANQADCgEIAQAAAA==.Snuggles:BAAANQADCgcIBwABNQAECgoKKwAhAJ4YAA==.',
So='Solára:BAABNQAECn8eAAMIAAoKpQ8LHQDuAAAgAAgKLAsnPQBfAQAIAAUKlRALHQDuAAAAAA==.',
Sp='Spellforge:BAAANQAECgMIAwAAAA==.Spinach:BAAANQAECgQIBAAAAA==.Sprath:BAAANQAECgQICwAAAA==.',
St='Staretra:BAABNQAECn9HAAMXAAoKMAY7cwCBAQAXAAoKMAY7cwCBAQAaAAcKBgk6NgByAQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.Stezz:BAAANQAECgEIAQAAAA==.',
Su='Sublimazee:BAAANQAECgQIBAAAAA==.Sumar:BAAANQABCgEIAQAAAA==.Summersky:BAAANQAECgEIAQAAAA==.Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECn9NAAIKAAoK2RTDUQDMAQAKAAoK2RTDUQDMAQAAAA==.Talerah:BAABNQAECn8zAAIPAAoKKgwfPwCfAQAPAAoKKgwfPwCfAQAAAA==.Taliliia:BAAANQABCgIIAgAAAA==.Talilyia:BAAANQAECgMICQAAAA==.Talohae:BAACNQAFFH8HAAIjAAMKVx31CgAfAQAjAAMKVx31CgAfAQA1AAQKfzUAAiMACgrSJGEBAMMDACMACgrSJGEBAMMDAAAA.Tanjent:BAAANQAECgcIEgAAAA==.Tapio:BAAANQAECgUIBwAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgoKGwALAKcYAA==.Tatsumå:BAABNQAECn8bAAILAAoKpxj+OABpAgALAAoKpxj+OABpAgAAAA==.Tavv:BAABNQAECn8kAAIbAAgKFghYGwCvAQAbAAgKFghYGwCvAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.Terrix:BAAANQAECgYIBgABNQAECgYIEwAGAAAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQAECgUIDAAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUICQAGAAAAAA==.Thoghar:BAAANQABCgEIAQABNQADCgMIAwAGAAAAAA==.Thorrs:BAABNQAECn8rAAIZAAoKxQ+zWQAWAgAZAAoKxQ+zWQAWAgAAAA==.Thuglifé:BAABNQAECn8cAAITAAkK1gqhGQCaAQATAAkK1gqhGQCaAQAAAA==.Thundacat:BAABNQAECn86AAIYAAoKeSXLAQBmAwAYAAoKeSXLAQBmAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgcIFAAHALwGAA==.Tidemaiden:BAABNQAECn8xAAMKAAoKmBE+bgDAAQAKAAoKmBE+bgDAAQAbAAMKtwMlMwBNAAAAAA==.Tipsymancer:BAABNQAECn9HAAIeAAoKnB+xAwCjAgAeAAoKnB+xAwCjAgAAAA==.',
Tr='Treesus:BAABNQAECn8mAAIcAAoKeg92NgA4AgAcAAoKeg92NgA4AgAAAA==.Treëfrog:BAAANQABCgIIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgoKHgAMAP0WAA==.Troutman:BAAANQAECgEIAQAAAA==.Tryantjhg:BAAANQABCgQIBAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAABNQAECn8eAAMMAAoK/RbHeQC5AQAMAAoK/RbHeQC5AQAoAAEKAABcEAAAAAAAAA==.',
['Tø']='Tøken:BAAANQADCgUIBQAAAA==.',
Ur='Ursia:BAAANQADCggICAAAAA==.Uruloke:BAAANQADCgYIDAABNQAECgEIAQAGAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Valuable:BAAANQAECgcIBwAAAA==.Vashdin:BAABNQAECn8aAAIVAAYKZhVF8wD+AAAVAAYKZhVF8wD+AAAAAA==.',
Ve='Velashis:BAABNQAECn8lAAMjAAoKrhkZHABVAgAjAAoKrhkZHABVAgAcAAIKUgK7swAwAAAAAA==.Velathanir:BAAANQAECgIIAgAAAA==.Venomable:BAABNQAECn8pAAMCAAkKzBPtIQC8AQACAAkKlBPtIQC8AQADAAUK9gwsOgCjAAAAAA==.Vermin:BAABNQAECn8uAAIZAAkKthq0PQB/AgAZAAkKthq0PQB/AgAAAA==.',
Vi='Vicvega:BAABNQAECn8WAAMCAAoKAguNeAA/AQACAAgK/wuNeAA/AQADAAcKCgavYQAuAQAAAA==.Vivif:BAABNQAECn9DAAQeAAoKix7RBgDZAgAeAAoKVB7RBgDZAgAiAAoKwRu8DgAxAgAfAAUK2B5wLgClAQAAAA==.Vivila:BAABNQAECn8ZAAISAAgKvRWWDQCoAQASAAgKvRWWDQCoAQABNQAECgoKOAAgAEccAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgcIEAAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECn8XAAMnAAgKQhlzGADBAQAnAAcKmxZzGADBAQApAAcK+RJYJAChAQAAAA==.',
Vu='Vugnus:BAABNQAECn8iAAMZAAcKiRJrmADXAAAZAAYK4g1rmADXAAAKAAQK3woHvQCfAAAAAA==.Vugowulf:BAAANQADCggIEAAAAA==.',
['Vé']='Véxx:BAABNQAECn8dAAIIAAgKihb1DQBtAQAIAAgKihb1DQBtAQAAAA==.',
['Vï']='Vïx:BAAANQAECgYIBQAAAA==.',
Wa='Wadewilson:BAAANQADCgcICwAAAA==.Waltahflight:BAAANQAECgEIAQAAAA==.Wannan:BAAANQADCggICAAAAA==.Waye:BAABNQAECn8UAAMYAAkKOB/5DgB0AgAYAAgKjx/5DgB0AgAlAAMK4xmPIwDlAAAAAA==.',
We='Westrin:BAACNQAFFH8KAAIdAAUKpxaiAQAsAQAdAAUKpxaiAQAsAQA1AAQKfzQAAh0ACgpSJfcAACsDAB0ACgpSJfcAACsDAAAA.',
Wi='Wiegraf:BAAANQADCgYICQABNQAECgoKPQAEADYcAA==.Wife:BAABNQAECn8aAAMVAAkKwSExPQDeAgAVAAkKwSExPQDeAgAEAAMK+wUF/ACFAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUICQAAAA==.',
['Wà']='Wàr:BAAANQADCgYIBgAAAA==.',
Ya='Yacob:BAABNQAECn8oAAMXAAoK4hpuOQBWAgAXAAoK4hpuOQBWAgAaAAMKTw+QXACTAAAAAA==.Yaecob:BAAANQAECgQIBAABNQAECgoKKAAXAOIaAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAGAAAAAA==.',
Ye='Yenneferr:BAABNQAECn8dAAIgAAoKTwypMAC8AQAgAAoKTwypMAC8AQAAAA==.',
Yh='Yhwach:BAABNQAECn8qAAIFAAoKCBaXHAAZAgAFAAoKCBaXHAAZAgAAAA==.',
Yi='Yildiz:BAAANQADCggICAAAAA==.',
Ym='Ymir:BAABNQAECn8eAAIVAAkKiBl3YgBzAgAVAAkKiBl3YgBzAgABNQAECgEIAQAGAAAAAA==.',
Yo='Yosaf:BAABNQAECn8wAAIVAAoKRh4mNACTAgAVAAoKRh4mNACTAgAAAA==.',
Yu='Yuie:BAAANQAECgQIBwABNQAECgcIFAAHALwGAA==.Yukitaiga:BAAANQAECgIIAgABNQABCgQIBQAGAAAAAA==.',
Za='Zaft:BAABNQAECn9GAAMVAAoKgBOHdQDjAQAVAAoKhRKHdQDjAQAUAAIKPBeHWgByAAAAAA==.Zaha:BAABNQAECn8UAAIMAAgKDyBJhwBwAgAMAAgKDyBJhwBwAgAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQAECgEIAQAAAA==.',
Ze='Zedfrey:BAABNQAECn8WAAIVAAcKMAmj7QBBAQAVAAcKMAmj7QBBAQAAAA==.Zem:BAABNQAECn8wAAMRAAoKTho7MQB6AgARAAoKTho7MQB6AgASAAIK4AkMJgB9AAAAAA==.Zemangoose:BAAANQAECgIIAgAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECn8wAAIEAAoKaxf2RQBOAgAEAAoKaxf2RQBOAgAAAA==.Zeroultra:BAABNQAECn8xAAMSAAkKsBWsDgCUAQASAAgKLxesDgCUAQARAAIKBQvaCgFkAAAAAA==.Zeräse:BAAANQAECgIIAgABNQAECgoKPQAEADYcAA==.Zeusmos:BAABNQAECn8yAAIfAAoK1iLVBQAUAwAfAAoK1iLVBQAUAwAAAA==.',
Zi='Zithenex:BAABNQAECn8hAAInAAcKkQhwFADwAAAnAAcKkQhwFADwAAAAAA==.',
Zu='Zugleesh:BAAANQAFFAEIAgAAAA==.',
Zw='Zwar:BAAANQAECgEIAQAAAA==.',
['Ál']='Álister:BAABNQAECn8aAAISAAYK3A7VGgDhAAASAAYK3A7VGgDhAAAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['Ér']='Éragon:BAAANQABCgIIAgAAAA==.',
['ßo']='ßoru:BAAANQAECgMIBQABNQAECggIEwAGAAAAAA==.',
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
