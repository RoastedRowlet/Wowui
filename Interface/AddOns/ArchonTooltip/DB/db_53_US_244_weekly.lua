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

local lookup = {'Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Protection','Paladin-Retribution','Mage-Frost','Priest-Holy','Druid-Guardian','Shaman-Elemental','Hunter-Marksmanship','Priest-Shadow','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Hunter-Survival','Monk-Mistweaver','Druid-Restoration','Evoker-Preservation','Priest-Discipline','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECn83AAQBAAoKqhumBgBeAgABAAkKXhmmBgBeAgACAAEKnR+AugBfAAADAAEKvhvkUwBSAAAAAA==.',
Ab='Abracadaver:BAAANQAECgYICAAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgAEAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECn83AAIFAAkKQB2lIACvAgAFAAkKQB2lIACvAgAAAA==.Aegon:BAAANQAECgEIAQAAAA==.Aenledron:BAAANQAECgEIAQABNQAECggIEgAGAAAAAA==.Aeturnas:BAABNQAECn8/AAIEAAoKCSQyDgBYAwAEAAoKCSQyDgBYAwAAAA==.',
Af='Afukeenba:BAAANQAECgIIAgAAAA==.',
Ag='Aghori:BAAANQAECgQIBQAAAA==.',
Ai='Aire:BAABNQAECn8UAAMHAAcKvAbqXwD+AAAHAAcK+wXqXwD+AAAIAAQKigX/JgCBAAAAAA==.',
Al='Alanima:BAAANQAECgUIBwAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAABNQAECn8WAAIJAAkKKxIzgABLAQAJAAkKKxIzgABLAQABNQAECgoKMAAKADsaAA==.Alittlegeeky:BAAANQADCgIIAgABNQAECgcIFAALALscAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgYICQAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAGAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECn9NAAILAAoK6B5QGwDJAgALAAoK6B5QGwDJAgAAAA==.',
An='Andralynn:BAAANQAECgQIAwAAAA==.Aneas:BAAANQADCggICAAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQABCgQIBQAGAAAAAA==.',
Aq='Aquilas:BAAANQAECgYIBgAAAA==.',
Ar='Arassa:BAAANQADCgcIBwAAAA==.Archsparks:BAAANQABCgEIAQAAAA==.Arcstream:BAABNQAECn8kAAIMAAoK5Q1lXgDrAQAMAAoK5Q1lXgDrAQAAAA==.Arctica:BAAANQAECgQICwAAAA==.Arete:BAAANQADCggIEAAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAABNQAECn8bAAINAAYKJwuzTADEAAANAAYKJwuzTADEAAAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Aspir:BAEANQADCgcIBwABNQAFFAYIEgAOAAUWAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECn88AAIPAAoKYBlWBgCoAgAPAAoKYBlWBgCoAgAAAA==.',
At='Atåvvi:BAAANQADCgQIBAAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAABNQAECn8yAAILAAkKLxcQaABEAgALAAkKLxcQaABEAgAAAA==.',
Ay='Ayano:BAABNQAECn9RAAIMAAoKaCNSGABzAwAMAAoKaCNSGABzAwAAAA==.Ayulur:BAAANQAECgEIBAAAAA==.',
Az='Azurefalls:BAABNQAECn80AAIFAAoKRyFkCwBYAwAFAAoKRyFkCwBYAwAAAA==.',
Ba='Badfiremage:BAABNQAECn8nAAMJAAoKURq/RgB+AgAJAAoKURq/RgB+AgAPAAEKVwLGhgAhAAAAAA==.Balthïer:BAABNQAECn89AAIEAAoKNhyGKgBtAgAEAAoKNhyGKgBtAgAAAA==.Bark:BAABNQAECn86AAQQAAoKLCKiGABWAwAQAAoK3yGiGABWAwARAAUK0hvAEwBkAQASAAMK5h4JHAAMAQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAABNQAECn8tAAMTAAkKVSb7AwB8AwATAAkKVSb7AwB8AwAUAAcKUhPz2QASAQABNQAECgoKPgAFAAYmAA==.Beeb:BAABNQAECn8iAAIIAAkK0CNnAQArAwAIAAkK0CNnAQArAwABNQAECgoKPgAFAAYmAA==.Beefisting:BAAANQADCgIIAgABNQAECgoKPgAFAAYmAA==.Beelzébubba:BAAANQADCgIIAgAAAA==.Beethicc:BAAANQAECggICAABNQAECgoKPgAFAAYmAA==.Beezz:BAABNQAECn8+AAIFAAoKBiaSAwC4AwAFAAoKBiaSAwC4AwAAAA==.Beliara:BAAANQAECgQIBwAAAA==.Belwar:BAAANQAECgQICAAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECn8/AAMVAAoKEB+3BADZAgAVAAoKEB+3BADZAgAMAAEKAACy4wEhAAAAAA==.Bishopwr:BAABNQAECn8uAAMQAAoKDxIPUgD2AQAQAAoKDxIPUgD2AQASAAUKvgFRNgCAAAAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBwAAAA==.Bocay:BAAANQAECgYIBgABNQAECgoKJwAWADkaAA==.Bohica:BAAANQAECgYICQAAAA==.',
Br='Branch:BAAANQAECgEIAQABNQAECgkJKAAFAMUTAA==.Brecks:BAAANQAECgcIEAAAAA==.Brem:BAABNQAECn82AAIMAAoKFR3qXADGAgAMAAoKFR3qXADGAgAAAA==.Briara:BAAANQAECgQIBwAAAA==.Broknüs:BAAANQAECgMIBAAAAA==.Broníx:BAAANQAECgQICQAAAA==.Bropeep:BAABNQAECn8uAAMNAAoKMx67IQDAAgANAAoKMx67IQDAAgAOAAIKnQnhmQBgAAAAAA==.',
Bu='Bullshott:BAAANQAECgMIBwAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggICwAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgcIGwAXAAoDAA==.Calyen:BAAANQAECgMIBAABNQAECgYIBgAGAAAAAA==.Carartha:BAABNQAECn8uAAIUAAkKrgfAyQAsAQAUAAkKrgfAyQAsAQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgoKJwAJAFEaAA==.Carrots:BAABNQAECn8WAAILAAYK4Qvh1wDmAAALAAYK4Qvh1wDmAAAAAA==.Cashmoolah:BAABNQAECn9JAAMUAAoKXhOzXwACAgAUAAoKXhOzXwACAgATAAIKzgFZbAAfAAAAAA==.Catfight:BAAANQAECgUIEQAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAACNQAFFH8QAAMYAAcKDRArCgAhAQAYAAYK/QwrCgAhAQAKAAEKHAFRLwA0AAA1AAQKf1gAAhgACgozHdIcAHsCABgACgozHdIcAHsCAAAA.Change:BAAANQAECgQIBAAAAA==.Charcoal:BAABNQAECn81AAMPAAoKYhYhCQBoAgAPAAkKtRMhCQBoAgAJAAgKQRVKhADbAQAAAA==.Chasebakes:BAABNQAECn89AAMZAAoKKiKwDQAFAwAZAAoKYR+wDQAFAwALAAMK6Bu7/QCcAAAAAA==.Cheesecake:BAABNQAECn8eAAIPAAcKaQtIDQDfAAAPAAcKaQtIDQDfAAAAAA==.Choks:BAABNQAECn8ZAAIRAAYKhgh/HAC0AAARAAYKhgh/HAC0AAAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAABNQAECn8nAAIaAAoKeiGqBgD6AgAaAAoKeiGqBgD6AgABNQAFFAcIGQAbAPAcAA==.',
Ci='Cindiyoohoo:BAABNQAECn9AAAIcAAoKcxysEQCLAgAcAAoKcxysEQCLAgAAAA==.Cizmac:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQADCgUIBQAAAA==.Claus:BAAANQADCggICAABNQAECgoKJwATAKgOAA==.',
Cm='Cmdrshepard:BAAANQADCgEIAQABNQAECgkJLAAPAAgRAA==.',
Co='Corruptdata:BAAANQADCgMIBgAAAA==.Cownado:BAAANQAECgUIDgABNQAECgYIBgAGAAAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.Crimzzen:BAAANQADCggICAAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgUIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgYIEQABNQAECgcIFAAHALwGAA==.',
Cy='Cyfelen:BAABNQAECn9FAAQPAAoK0B4sAgBYAgAJAAoKZxjSRACEAgAPAAoKtRwsAgBYAgAdAAIKsB28HQCOAAAAAA==.Cynleel:BAAANQAECgYICgAAAA==.Cyris:BAAANQAECgcIBgAAAA==.',
Da='Dahrena:BAAANQAECgYIDAAAAA==.Darthmall:BAAANQAECgYIEwABNQAFFAQICwAXAJQTAA==.Dawgg:BAAANQAECggICQAAAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
Db='Dboy:BAAANQAECgEIAwAAAA==.',
De='Deadgeknight:BAAANQAECgQIBAAAAA==.Delyta:BAAANQAECggICQAAAA==.Demidru:BAABNQAECn8gAAIXAAoKoxxREwAuAgAXAAoKoxxREwAuAgAAAA==.Demonicdawn:BAAANQAECgQIBAAAAA==.Derat:BAAANQAECgEIAQAAAA==.Deucalion:BAAANQADCgcICQAAAA==.Deveruxx:BAAANQADCgEIAQAAAA==.',
Di='Dibbydab:BAAANQAECggIEwAAAA==.',
Dj='Django:BAABNQAECn8eAAIcAAkKkRbvJgCcAgAcAAkKkRbvJgCcAgAAAA==.Djehrtey:BAAANQAECgUICwAAAA==.Djinni:BAABNQAECn8oAAMeAAkKmh1rBgDnAgAeAAkKmh1rBgDnAgAfAAQKXRFrQQCVAAABNQAFFAQICwAXAJQTAA==.Djwiltumble:BAAANQAECgEIAQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAABNQAECn8hAAIOAAoKsRYAPgCOAQAOAAoKsRYAPgCOAQAAAA==.',
Dr='Dracnahr:BAAANQAECgcIEgAAAA==.Drenleah:BAABNQAECn8ZAAMPAAoKng+TEwDUAQAPAAgK7Q6TEwDUAQAJAAgKIQwzZwCNAQABNQAECgoKMwAgABkbAA==.Drenlee:BAAANQAECgIIAwABNQAECgoKMwAgABkbAA==.Dromokafrapp:BAAANQAECgIIAgAAAA==.',
Du='Dumblegear:BAABNQAECn8aAAIMAAgKeBryfQCCAgAMAAgKeBryfQCCAgAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAABNQAECn8wAAIKAAoKOxq1KQC8AgAKAAoKOxq1KQC8AgAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgoKMwAKAAoSAA==.',
Dy='Dymonic:BAAANQAECgEIAQABNQAECgIIBAAGAAAAAA==.Dysdayne:BAAANQAECgQICwAAAA==.',
['Dë']='Dëathx:BAAANQADCgcIBwABNQAECggILQARAMsVAA==.',
Ed='Edinna:BAABNQAECn8wAAIMAAoK5QkiegClAQAMAAoK5QkiegClAQAAAA==.',
Ei='Eileamaid:BAAANQAECgMIBAAAAA==.',
El='Elessedil:BAAANQAECgUICQAAAA==.Ellemystic:BAAANQAECgQIBwAAAA==.Elpally:BAAANQADCgMIAwAAAA==.Elspeth:BAAANQADCggICAABNQAECgcIGwAXAAoDAA==.Elyriana:BAAANQAECgcIDwAAAA==.',
Em='Emila:BAEANQAECgcIDQABNQAECgoKNwALADsiAA==.Emirozu:BAAANQADCgUIBQAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECggIEwAAAA==.Emriq:BAAANQAECgMIBQAAAA==.',
En='Enrique:BAABNQAECn9YAAMUAAoKuyRXIwA3AwAUAAoKuyRXIwA3AwATAAEK0xP1agA8AAAAAA==.',
Ep='Epedemik:BAAANQAECgEIAgAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECgkJKAAFAMUTAA==.Erusdh:BAAANQAECgMIAwAAAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECggIBgAAAA==.',
Ev='Eveninwillow:BAAANQADCggICAAAAA==.Evöö:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgUICgAAAA==.',
Fa='Faeng:BAABNQAFFH8LAAIXAAQKlBPuAwDHAAAXAAQKlBPuAwDHAAAAAA==.Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgcIDgAAAA==.Faubito:BAAANQAECgYIBwAAAA==.',
Fe='Fearlesfreep:BAABNQAECn9HAAILAAoKahZcOgBUAgALAAoKahZcOgBUAgAAAA==.Febz:BAAANQAECgUICQAAAA==.Felatonin:BAABNQAECn8ZAAIgAAgK6B+8GgCCAgAgAAgK6B+8GgCCAgAAAA==.Felfüry:BAABNQAECn9IAAMIAAoKgRNgDwA5AQAHAAoK0hJIKQCtAQAIAAkKjg9gDwA5AQAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQAECgEIAQAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAABNQAECn8hAAMZAAkK3Q+/KQAIAQAZAAYKFg2/KQAIAQALAAUKQhGFzQD8AAAAAA==.',
Fl='Flafy:BAAANQAECgEIAQAAAA==.',
Fo='Fogassann:BAAANQAECgUIBQABNQAECgoKPgASAMchAA==.Foggpy:BAABNQAECn89AAIdAAoKwiI4AQBWAwAdAAoKwiI4AQBWAwAAAA==.Fogtotem:BAAANQAECgUIBgABNQAECgoKPQAdAMIiAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUIDQAAAA==.Fröstmöurne:BAABNQAECn84AAIFAAkKag1cNgBeAQAFAAkKag1cNgBeAQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.Furydeath:BAAANQAECgIIAgAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQAECgUIBQAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgcIGgAJAHUdAA==.Genghiskhan:BAABNQAECn8sAAINAAkKxRrAKgCLAgANAAkKxRrAKgCLAgAAAA==.Geren:BAAANQAECggIDwAAAA==.Geret:BAABNQAECn8pAAIUAAgKhRPsjgAHAgAUAAgKhRPsjgAHAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQAECgEIAQAAAA==.',
Gl='Glitchy:BAABNQAECn9FAAIcAAoKYRZOHAAPAgAcAAoKYRZOHAAPAgAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECn9FAAITAAoKqR37DgCtAgATAAoKqR37DgCtAgAAAA==.Goldfarmr:BAABNQAECn8WAAIWAAoK5xFSUwApAgAWAAoK5xFSUwApAgABNQAECgoKPgAMAIMfAA==.Goldglazeher:BAABNQAECn8+AAIMAAoKgx80OgATAwAMAAoKgx80OgATAwAAAA==.Goldrawr:BAAANQAECgYICgABNQAECgoKPgAMAIMfAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQAECgEIAQAAAA==.Graimy:BAAANQAECgEIAQAAAA==.Grasshoppër:BAAANQAECgEIAQAAAA==.Greeley:BAABNQAECn8qAAIZAAoKpB86DABsAgAZAAoKpB86DABsAgAAAA==.Greganir:BAABNQAECn8YAAMVAAgKdxroGwARAQAMAAgKaxaGrQAnAgAVAAQKOhroGwARAQABNQAECggIGQAFAJMaAA==.Gregdapro:BAABNQAECn8ZAAIFAAgKkxqXNwArAgAFAAgKkxqXNwArAgAAAA==.Grimshadez:BAAANQAECgEIAQAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAABNQAECn8ZAAQSAAYK0gpEJwCtAAASAAYK0gpEJwCtAAAQAAQKaQZ5GwGlAAARAAQKKwYTJABwAAAAAA==.',
Gy='Gyathew:BAABNQAECn8qAAIYAAkKRyBWEwBXAwAYAAkKRyBWEwBXAwAAAA==.',
Ha='Hagunn:BAABNQAECn8ZAAMQAAkKPxdPgwATAgAQAAkKxxRPgwATAgARAAMK9Ru6GgD6AAAAAA==.Happerixie:BAAANQADCgcIBwAAAA==.',
He='Heatfrezze:BAAANQAECggIDAAAAA==.Heladaa:BAAANQADCgMIAwAAAA==.Hervöralvit:BAAANQADCgIIAgAAAA==.Hevy:BAABNQAECn8zAAIgAAoKGRsgEwAdAgAgAAoKGRsgEwAdAgAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holygriff:BAAANQAECgIIAgAAAA==.Holyshots:BAABNQAECn9HAAIUAAoK5ROdaADtAQAUAAoK5ROdaADtAQAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Id='Idrizzt:BAAANQAECgQICQAAAA==.',
Ig='Ignore:BAAANQAECggICwABNQAECgoKJwAJAFEaAA==.',
Io='Iobo:BAABNQAECn8aAAIhAAYKJQsjCwD1AAAhAAYKJQsjCwD1AAAAAA==.',
Ir='Ironhidez:BAABNQAECn82AAIUAAkKYwr4vQBAAQAUAAkKYwr4vQBAAQAAAA==.',
Is='Isaarek:BAAANQAECgEIAQAAAA==.Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAABNQAECn8dAAILAAgKcBk6kAB5AQALAAgKcBk6kAB5AQABNQAECgoKMAAKADsaAA==.',
Iz='Izerol:BAABNQAECn9fAAIfAAoK/SSAAgBTAwAfAAoK/SSAAgBTAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.Jaylea:BAAANQAECgUIBQAAAA==.',
Je='Jeb:BAAANQAECgEIAQABNQAECggIGgAEAP0dAA==.Jebopally:BAABNQAECn8aAAMEAAgK/R2dPAByAgAEAAcKiB6dPAByAgAUAAcKnhk/qADPAQAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAABNQAECn8dAAIJAAcKfxlGfwDoAQAJAAcKfxlGfwDoAQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUIDgAAAA==.',
Jo='Joehex:BAABNQAECn8+AAISAAkKgiBaBwDmAgASAAkKgiBaBwDmAgAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQAECgEIAQAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAABNQAECn8cAAIQAAgKVhKZewB9AQAQAAgKVhKZewB9AQAAAA==.',
Ka='Kaidoe:BAAANQAECgYIBwAAAA==.Kaleesh:BAACNQAFFH8QAAIbAAYKECNoAQBcAQAbAAYKECNoAQBcAQA1AAQKfzYAAhsACgpLJjwBAFkDABsACgpLJjwBAFkDAAAA.Kallux:BAABNQAECn9CAAIFAAoKrh8HDQC/AgAFAAoKrh8HDQC/AgAAAA==.Kalma:BAABNQAECn8vAAIFAAoKyx6sFQBPAgAFAAoKyx6sFQBPAgAAAA==.Kananga:BAABNQAECn8XAAIWAAYKChOKfABLAQAWAAYKChOKfABLAQAAAA==.Kasca:BAABNQAECn8ZAAIcAAcKQAhoWwCiAAAcAAcKQAhoWwCiAAAAAA==.Kato:BAAANQAECgUICQABNQAECgoKNwAbAI0aAA==.',
Ke='Kerah:BAAANQADCggICAABNQAECgoKMAAKADsaAA==.',
Kh='Khadran:BAAANQADCgIIAwAAAA==.Khalyraa:BAAANQAECgUIDgAAAA==.',
Ki='Kiermac:BAABNQAECn8VAAILAAgKuwn1twAnAQALAAgKuwn1twAnAQAAAA==.Kindred:BAAANQADCgQIBAAAAA==.Kiragrande:BAABNQAECn8qAAIiAAoKvhGgFQAiAgAiAAoKvhGgFQAiAgAAAA==.Kiriku:BAABNQAECn8XAAIcAAUKhwwPVAC8AAAcAAUKhwwPVAC8AAAAAA==.Kithane:BAAANQADCgMIBgAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgUIBQAAAA==.Kotok:BAABNQAECn8XAAMKAAcKsAssiAAHAQAKAAcKsAssiAAHAQAbAAEKAADqNwAwAAAAAA==.',
Kr='Krelein:BAABNQAECn8gAAITAAcKXhVJKAAaAQATAAcKXhVJKAAaAQAAAA==.',
Ku='Kurth:BAAANQAECgQIBAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
['Ká']='Káinan:BAAANQADCgIIAgAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECn8ZAAIfAAcK4yIZGACIAgAfAAcK4yIZGACIAgAAAA==.Leenaashala:BAABNQAECn8ZAAILAAgKQRKtgwCWAQALAAgKQRKtgwCWAQABNQAECgoKNwAbAI0aAA==.Levin:BAAANQAECgIIBQAAAA==.',
Li='Linissa:BAAANQAECgMICAABNQAFFAQICwAXAJQTAA==.',
Ll='Llght:BAABNQAECn8ZAAMWAAoKfhxQHwDQAgAWAAoKfhxQHwDQAgAaAAIKqgZSbwBKAAAAAA==.',
Lo='Logankord:BAABNQAECn88AAIRAAkKGiENBQDaAgARAAkKGiENBQDaAgAAAA==.Lokeira:BAABNQAECn8zAAIKAAoKChJqXQD3AQAKAAoKChJqXQD3AQAAAA==.Lonki:BAAANQAECgQIAwAAAA==.Lono:BAAANQAECgYIBwAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luuniren:BAAANQAECgEIAQABNQAECgQICwAGAAAAAA==.Luvbug:BAABNQAECn8UAAILAAcKuxzRagA+AgALAAcKuxzRagA+AgAAAA==.',
Ly='Lyais:BAAANQAECgQICwAAAA==.Lyara:BAACNQAFFH8LAAIKAAcK5xeMCADGAQAKAAcK5xeMCADGAQA1AAQKfzIAAwoACgqFHucrALMCAAoACgqFHucrALMCABgACQqyGwclAEECAAAA.Lythos:BAABNQAECn8oAAIFAAkKxRM3TgC9AQAFAAkKxRM3TgC9AQAAAA==.',
['Lø']='Lørdøfßud:BAABNQAECn8+AAMSAAoKxyEJBADkAgASAAoKxyEJBADkAgAQAAEKAAANUAE2AAAAAA==.',
Ma='Machomans:BAAANQAECgQIBwABNQAECgcIEgAGAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Magicmeat:BAAANQAECgQIBgAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Makimá:BAAANQADCgYIBgABNQAECgoKFgACAAILAA==.Mandragora:BAAANQADCgIIAgAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECn9KAAIDAAoK3RFsDAD4AQADAAoK3RFsDAD4AQAAAA==.Mastamojo:BAABNQAECn8fAAIEAAgKwgdiiwB6AQAEAAgKwgdiiwB6AQAAAA==.Mattheals:BAABNQAECn81AAMWAAoKMRmrJwCcAgAWAAoKMRmrJwCcAgAaAAEKAAA/dQAAAAAAAA==.',
Mc='Mcmurphy:BAAANQAECgMIAwAAAA==.',
Me='Meanieman:BAAANQABCggIDAAAAA==.Meanpaula:BAAANQADCgMIAwAAAA==.Meissen:BAABNQAECn8sAAIPAAkKCBE8BQCSAQAPAAkKCBE8BQCSAQAAAA==.Melendaren:BAAANQAECgEIAQAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Meowandi:BAAANQAECgEIAQAAAA==.Messìah:BAABNQAECn8lAAMcAAYK+g8rRgD4AAAcAAYK+g8rRgD4AAAjAAQKwg0hTAC2AAAAAA==.Metamonster:BAABNQAECn8XAAMNAAgKRAsRPAATAQANAAgKkAgRPAATAQAFAAMKFhG4ewBoAAAAAA==.',
Mi='Mickie:BAABNQAECn8bAAIXAAcKCgPLPQDGAAAXAAcKCgPLPQDGAAAAAA==.Miniav:BAAANQAECgQIBwAAAA==.Mirko:BAAANQAECgEIAQABNQAECgcIEgAGAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBwAAAA==.',
Mo='Mockery:BAABNQAECn9RAAIMAAoKTxDGVQACAgAMAAoKTxDGVQACAgAAAA==.Mokokniki:BAABNQAECn8nAAIjAAoK7xKILQCvAQAjAAoK7xKILQCvAQAAAA==.Moneie:BAAANQAECgMIAwAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAABNQAECn8UAAIkAAcKmhaPJgCGAQAkAAcKmhaPJgCGAQAAAA==.Morticiá:BAAANQAECgcIBwAAAA==.Mourningstar:BAACNQAFFH8MAAINAAYKRRmMBQDLAQANAAYKRRmMBQDLAQA1AAQKfyQAAw0ACgp6I+EUABIDAA0ACAqAI+EUABIDAAUABgr0HrdiAGcBAAE1AAUUBwgWAAUAzxkA.Moxytonic:BAAANQAECgEIAQAAAA==.Mozaic:BAABNQAECn9KAAISAAoKUyBZBADZAgASAAoKUyBZBADZAgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQAECgQIDQAAAA==.Naec:BAAANQADCgEIAQABNQAECgQIBgAGAAAAAA==.Naek:BAAANQAECgQIBgAAAA==.Nalthis:BAAANQAECggICQAAAA==.',
Ne='Necromus:BAAANQAECgUIDQAAAA==.Nekra:BAABNQAECn8cAAMcAAcKCQxIRQD8AAAcAAcKCQxIRQD8AAAXAAUKLAaeUwBkAAAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcIDwAAAA==.',
No='Nocturnum:BAACNQAFFH8FAAIgAAMKlwq8EQCCAAAgAAMKlwq8EQCCAAA1AAQKf0MAAiAACgrGItIHAFQDACAACgrGItIHAFQDAAAA.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
['Nø']='Nøir:BAAANQAECgIIAgAAAA==.',
Oh='Oha:BAAANQAECgMIBAAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBQABNQAECgQICwAGAAAAAA==.',
On='Onepuffman:BAACNQAFFH8ZAAIbAAcK8BzxAAA9AgAbAAcK8BzxAAA9AgA1AAQKfz0AAhsACgrpJPwBAEADABsACgrpJPwBAEADAAAA.Onetwocowpow:BAABNQAECn9HAAIiAAoK7BNFDgAjAgAiAAoK7BNFDgAjAgAAAA==.',
Or='Ordanith:BAABNQAECn84AAIUAAoKYiGtIgA5AwAUAAoKYiGtIgA5AwAAAA==.Orionn:BAACNQAFFH8ZAAILAAcKyBv1AgDGAQALAAcKyBv1AgDGAQA1AAQKf18AAwsACgrcJr8AAJoDAAsACgrcJr8AAJoDABkAAgr9EpVDAIAAAAAA.',
Os='Osø:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAABNQAECn8xAAQiAAoKwhVJFQAnAgAiAAgKfhZJFQAnAgAfAAkK/A9EJgBQAQAeAAEKDw4qMQA1AAAAAA==.',
Ow='Owlette:BAAANQAECgQIBAAAAA==.Owlxero:BAAANQAECgIIAgAAAA==.',
Pa='Patelz:BAAANQADCgYIBgAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAGAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pingfan:BAAANQAECgEIAgAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYIEQAAAA==.',
Pr='Praystation:BAAANQAECgEIAwABNQAECgcIFAAkAJoWAA==.Problem:BAAANQAECgYIBgAAAA==.',
Ps='Psygon:BAAANQADCgYIBgAAAA==.',
Qu='Quora:BAAANQABCggIEgAAAA==.',
Ra='Raelone:BAABNQAECn8sAAMPAAoKIhelCAAtAQAPAAcKpRelCAAtAQAdAAQKmBU1FgDnAAAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECgcIEwAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIDAAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECn88AAILAAoKIxhmSgCOAgALAAoKIxhmSgCOAgAAAA==.Ranoa:BAABNQAECn8UAAITAAgKqxBzKwCBAQATAAgKqxBzKwCBAQABNQAECgoKMgAXAN0eAA==.Rant:BAAANQAECgUICwAAAA==.Ravencraw:BAAANQADCgYICgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redishpanda:BAAANQADCgYIBgAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgYIDAAAAA==.Reo:BAAANQADCgQIBAAAAA==.Reverandrott:BAAANQAECgEIAQAAAA==.Reàper:BAAANQAECgEIAQAAAA==.',
Rh='Rheavin:BAAANQABCgQIBQAAAA==.Rhell:BAABNQAECn8bAAIEAAgKRSDoIwDbAgAEAAgKRSDoIwDbAgAAAA==.Rhellen:BAABNQAECn8uAAIWAAoKEB9CFgAUAwAWAAoKEB9CFgAUAwABNQAECggIGwAEAEUgAA==.',
Ri='Rinche:BAABNQAECn8VAAMYAAcK+wfYogBQAQAYAAcK+wfYogBQAQAKAAMKOgcx+AB6AAAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAABNQAECn8WAAIZAAgK8hY0JAAsAgAZAAgK8hY0JAAsAgAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAACNQAFFH8MAAIJAAQKywp2GQDMAAAJAAQKywp2GQDMAAA1AAQKfycAAgkACgqaEThsABkCAAkACgqaEThsABkCAAAA.',
Ru='Rudo:BAABNQAECn8bAAQZAAkKGxSVOACLAQALAAcKKRYXrQCqAQAZAAgKWwqVOACLAQAhAAMK6wdtDwCXAAABNQAECgoKFgACAAILAA==.Rumproblem:BAABNQAECn8zAAQWAAoKwxW6MABrAgAWAAkKFhe6MABrAgAaAAgKNgtwIwBSAQAlAAcKwA3CDwAuAQAAAA==.Ruri:BAAANQAECgMIBAABNQAECgoKFgACAAILAA==.',
Ry='Ryegar:BAAANQADCgcIDAABNQAECgoKPwAmABIbAA==.Ryeger:BAABNQAECn8/AAMmAAoKEhutCABIAgAmAAoKEhutCABIAgAcAAUK0gVmfgDTAAAAAA==.Ryuaoi:BAAANQAECgIIBgABNQABCgQIBQAGAAAAAA==.',
['Ró']='Róótbear:BAAANQAECgUIDAAAAA==.',
Sa='Safety:BAAANQAECgUIEgAAAA==.Salaine:BAAANQAECgQIBAAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAABNQAECn9DAAMUAAoKQxKKcADaAQAUAAoKQxKKcADaAQAEAAYKywWowAD7AAAAAA==.Samovaro:BAAANQADCgQIBAAAAA==.Sandbones:BAAANQAECgQIDQABNQAECgoKUQAMAE8QAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECn80AAMnAAoKThrZBQB8AgAnAAoKThrZBQB8AgAoAAUKPhiDEgD7AAAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sensou:BAAANQAECgYIBQABNQAECgoKNwAbAI0aAA==.Sentren:BAAANQAECgUIBwAAAA==.Seo:BAAANQADCgQIBAAAAA==.Setresh:BAABNQAECn88AAIhAAoK9hKwBACRAgAhAAoK9hKwBACRAgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shammatty:BAAANQAECgYIBgAAAA==.Shamwowhex:BAAANQAECgYICwAAAA==.Shangöh:BAAANQADCgUICQABNQAECgoKPQAEADYcAA==.Sharatira:BAAANQAECgMIBAAAAA==.Sherif:BAAANQAECgEIBAAAAA==.Shivver:BAAANQADCgQIBAAAAA==.Shivyn:BAABNQAECn9LAAIKAAoKsxeTJQCEAgAKAAoKsxeTJQCEAgAAAA==.Sholan:BAAANQAECgEIAQAAAA==.',
Si='Sibadeekay:BAABNQAECn9KAAMNAAoKGR4cEQBmAgANAAoK6BwcEQBmAgAFAAUKHCH+UACxAQAAAA==.Sickkid:BAABNQAECn80AAMRAAoKyxEUCgDaAQARAAkKVBEUCgDaAQAQAAcKxwlhwwB0AQAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgYIDQAAAA==.Sindrya:BAAANQAECgYIDgAAAA==.',
Sk='Skunkt:BAAANQADCgMIAwAAAA==.',
Sm='Smeef:BAAANQAECgEIBQAAAA==.Smoothvelvet:BAABNQAECn83AAIbAAoKjRpTCwBUAgAbAAoKjRpTCwBUAgAAAA==.',
Sn='Snooker:BAAANQADCgEIAQAAAA==.Snuggles:BAAANQADCgcIBwABNQAECgoKKwAhAJ4YAA==.',
So='Solára:BAABNQAECn8eAAMIAAoKpQ8LHQDuAAAgAAgKLAsnPQBfAQAIAAUKlRALHQDuAAAAAA==.Soulfryer:BAAANQAECgEIAgAAAA==.',
Sp='Spellforge:BAAANQAECgMIAwAAAA==.Spinach:BAAANQAECgQIBgAAAA==.Sprath:BAAANQAECgQICwAAAA==.',
St='Staretra:BAABNQAECn9HAAMWAAoKMAZpbAB/AQAWAAoKMAZpbAB/AQAaAAcKBgk6NgByAQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.Stezz:BAAANQAECgEIAQAAAA==.',
Su='Sublimazee:BAAANQAECgQIBAAAAA==.Sumar:BAAANQAECgEIAQAAAA==.Summersky:BAAANQAECgEIAQAAAA==.Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECn9KAAIKAAoK2RQKSwDPAQAKAAoK2RQKSwDPAQAAAA==.Talerah:BAABNQAECn8vAAIOAAoKGgvHPwCGAQAOAAoKGgvHPwCGAQAAAA==.Taliliia:BAAANQAECgEIAQAAAA==.Talilyia:BAAANQAECgMIBwAAAA==.Talohae:BAACNQAFFH8HAAIjAAMKVx31CgAfAQAjAAMKVx31CgAfAQA1AAQKfzUAAiMACgrSJGEBAMMDACMACgrSJGEBAMMDAAAA.Tanjent:BAAANQAECgYIDQAAAA==.Tapio:BAAANQAECgMIBQAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgoKGgALAA8YAA==.Tatsumå:BAABNQAECn8aAAILAAoKDxhKMwBpAgALAAoKDxhKMwBpAgAAAA==.Tavv:BAABNQAECn8kAAIbAAgKFghYGwCvAQAbAAgKFghYGwCvAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.Terrix:BAAANQAECgYIBgAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQAECgUICAAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUICgAGAAAAAA==.Thoghar:BAAANQABCgEIAQABNQADCgMIAwAGAAAAAA==.Thorrs:BAABNQAECn8rAAIYAAoKxQ+zWQAWAgAYAAoKxQ+zWQAWAgAAAA==.Thuglifé:BAABNQAECn8cAAISAAkK1gqhGQCaAQASAAkK1gqhGQCaAQAAAA==.Thundacat:BAABNQAECn86AAIXAAoKeSWhAQBoAwAXAAoKeSWhAQBoAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgcIFAAHALwGAA==.Tidemaiden:BAABNQAECn8tAAMKAAkKwRM+bgDAAQAKAAgKaRE+bgDAAQAbAAMKtwNPMABNAAAAAA==.Tipsymancer:BAABNQAECn9HAAIeAAoKnB9VAwCjAgAeAAoKnB9VAwCjAgAAAA==.',
Tr='Treesus:BAABNQAECn8mAAIcAAoKeg92NgA4AgAcAAoKeg92NgA4AgAAAA==.Treëfrog:BAAANQAECgEIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgoKHgAMAP0WAA==.Troutman:BAAANQAECgEIAQAAAA==.Tryantjhg:BAAANQAECgEIAQAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAABNQAECn8eAAMMAAoK/RaZcQC6AQAMAAoK/RaZcQC6AQApAAEKAACsDgAAAAAAAA==.',
['Tø']='Tøken:BAAANQADCgUIBQAAAA==.',
Ur='Ursia:BAAANQADCggICAAAAA==.Uruloke:BAAANQADCgYIDAABNQAECgEIAQAGAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAABNQAECn8aAAIUAAYKZhUn5QD/AAAUAAYKZhUn5QD/AAAAAA==.',
Ve='Velashis:BAABNQAECn8lAAMjAAoKrhkZHABVAgAjAAoKrhkZHABVAgAcAAIKUgK7swAwAAAAAA==.Velathanir:BAAANQAECgIIAgAAAA==.Venomable:BAABNQAECn8kAAMCAAkKzBPtIQC8AQACAAkKlBPtIQC8AQADAAUK9gz+NwCmAAAAAA==.Vermin:BAABNQAECn8uAAIYAAkKthq0PQB/AgAYAAkKthq0PQB/AgAAAA==.',
Vi='Vicvega:BAABNQAECn8WAAMCAAoKAgsWbgA/AQACAAgK/wsWbgA/AQADAAcKCgavYQAuAQAAAA==.Vivif:BAABNQAECn9AAAQeAAoKix7RBgDZAgAeAAoKVB7RBgDZAgAiAAoK1RjUEgDCAQAfAAUK2B5wLgClAQAAAA==.Vivila:BAAANQAECgUIDQABNQAECgoKMwAgABkbAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgcIEgAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECn8XAAMoAAgKQhlzGADBAQAoAAcKmxZzGADBAQAkAAcK+RJYJAChAQAAAA==.',
Vu='Vugnus:BAABNQAECn8bAAMYAAYK5REO2ADkAAAYAAUKlw4O2ADkAAAKAAQKyQkLuACYAAAAAA==.Vugowulf:BAAANQADCggIEAAAAA==.',
['Vé']='Véxx:BAABNQAECn8bAAIIAAcKXRaFEAApAQAIAAcKXRaFEAApAQAAAA==.',
['Vï']='Vïx:BAAANQAECgYIBQAAAA==.',
Wa='Wadewilson:BAAANQADCgcICwAAAA==.Waltahflight:BAAANQAECgEIBAAAAA==.Wannan:BAAANQADCggICAAAAA==.Waye:BAABNQAECn8UAAMXAAkKOB/5DgB0AgAXAAgKjx/5DgB0AgAmAAMK4xnlHwDmAAAAAA==.',
We='Westrin:BAACNQAFFH8JAAIdAAQK5x2iAQAsAQAdAAQK5x2iAQAsAQA1AAQKfzQAAh0ACgpSJdEAADMDAB0ACgpSJdEAADMDAAAA.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECgoKPQAEADYcAA==.Wife:BAABNQAECn8aAAMUAAkKwSExPQDeAgAUAAkKwSExPQDeAgAEAAMK+wUF/ACFAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUICgAAAA==.',
['Wà']='Wàr:BAAANQADCgYIBgAAAA==.',
Xi='Xieshifu:BAAANQAECgEIBQAAAA==.',
Ya='Yacob:BAABNQAECn8nAAMWAAoKORrjMwBbAgAWAAoKORrjMwBbAgAaAAMKTw+QXACTAAAAAA==.Yaecob:BAAANQAECgQIBAABNQAECgoKJwAWADkaAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAGAAAAAA==.',
Ye='Yenneferr:BAABNQAECn8dAAIgAAoKTwypMAC8AQAgAAoKTwypMAC8AQAAAA==.',
Yh='Yhwach:BAABNQAECn8hAAIFAAoK0RLOIADlAQAFAAoK0RLOIADlAQAAAA==.',
Yi='Yildiz:BAAANQADCggICAAAAA==.',
Ym='Ymir:BAABNQAECn8eAAIUAAkKiBl3YgBzAgAUAAkKiBl3YgBzAgABNQAECgEIAQAGAAAAAA==.',
Yo='Yosaf:BAABNQAECn8rAAIUAAoKcx0ZMQCQAgAUAAoKcx0ZMQCQAgAAAA==.',
Yu='Yuie:BAAANQAECgQIBwABNQAECgcIFAAHALwGAA==.Yukitaiga:BAAANQAECgIIAgABNQABCgQIBQAGAAAAAA==.Yule:BAAANQAECgEIAgAAAA==.',
Za='Zaft:BAABNQAECn9GAAMUAAoKgBNqagDpAQAUAAoKhRJqagDpAQATAAIKPBeHWgByAAAAAA==.Zaha:BAABNQAECn8UAAIMAAgKDyBJhwBwAgAMAAgKDyBJhwBwAgAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQAECgEIAQAAAA==.',
Ze='Zedfrey:BAABNQAECn8WAAIUAAcKMAmj7QBBAQAUAAcKMAmj7QBBAQAAAA==.Zem:BAABNQAECn8sAAMQAAoKThr4LAB+AgAQAAoKThr4LAB+AgARAAIK4AkMJgB9AAAAAA==.Zemangoose:BAAANQAECgIIBAAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECn8wAAIEAAoKaxf2RQBOAgAEAAoKaxf2RQBOAgAAAA==.Zeroultra:BAABNQAECn8tAAMRAAgKyxWsDgDDAQARAAcKmxesDgDDAQAQAAIKBQvo/wBlAAAAAA==.Zeräse:BAAANQAECgIIAgABNQAECgoKPQAEADYcAA==.Zeusmos:BAABNQAECn8vAAIfAAoK1iJJBQAWAwAfAAoK1iJJBQAWAwAAAA==.',
Zi='Zithenex:BAABNQAECn8aAAIoAAYKFQepFwCvAAAoAAYKFQepFwCvAAAAAA==.',
Zu='Zugleesh:BAAANQAFFAEIAgAAAA==.',
Zw='Zwar:BAAANQAECgEIAwAAAA==.',
['Ál']='Álister:BAABNQAECn8UAAIRAAUKRg0bIACRAAARAAUKRg0bIACRAAAAAA==.',
['Æó']='Æón:BAAANQAECgIIAwAAAA==.',
['Ér']='Éragon:BAAANQAECgEIBAAAAA==.',
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
