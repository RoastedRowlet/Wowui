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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Monk-Brewmaster','Warrior-Arms','Druid-Restoration','DemonHunter-Vengeance','Druid-Feral','Monk-Windwalker','Warlock-Demonology','Druid-Balance','Rogue-Assassination','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Evoker-Preservation','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Monk-Mistweaver','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Rogue-Subtlety',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-06-14',data={Ac='Achooe:BAABLgAECn8tAAMBAAkJsQpwHAAwAQABAAkJsQpwHAAwAQACAAEJJgJEygEZAAAAAA==.',
Ad='Ado:BAAALgAECgEJAQAAAA==.Adrel:BAAALgAECgUJBwAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn9GAAQGAAkJJxs7CACbAgAGAAkJJxs7CACbAgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBDMWwDIAQAJAAkJQBDMWwDIAQAAAA==.Agathorz:BAAALgAECgYJBwAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgcJEwAAAA==.',
Ak='Akiras:BAAALgADCggJDgAAAA==.',
Al='Alanala:BAAALgADCgYJBgAAAA==.Alarielle:BAAALgADCgYJBgABLgAECgkJIAAKAL0bAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAACLgAFFH8FAAIDAAMJgBmWLwDtAAADAAMJgBmWLwDtAAAuAAQKfzcAAwMACQnlJIQDADIDAAMACQnlJIQDADIDAAsABgn0EFsvAAgBAAAA.Allei:BAAALgAECgYJCQABLgAFFAQJEQAMAC4LAA==.Alyndrya:BAABLgAECn8qAAQEAAkJ5ReMEAAcAgAEAAkJcReMEAAcAgAFAAYJvxJcgAAcAQANAAEJkg0tNwAoAAAAAA==.Alyndrys:BAABLgAECn8jAAIOAAcJmhOrFgBdAQAOAAcJmhOrFgBdAQAAAA==.',
Am='Amelialynne:BAABLgAECn83AAIFAAkJNROlOQDeAQAFAAkJNROlOQDeAQAAAA==.Amithralia:BAABLgAECn8tAAIMAAkJmB+aCQAeAwAMAAkJmB+aCQAeAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SK/HADGAQAPAAYJ0SK/HADGAQAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8XAAIQAAgJAxdKQQDYAQAQAAgJAxdKQQDYAQAAAA==.',
Ao='Aohikari:BAAALgADCgYJCgABLgAFFAkJLgAMAE8eAA==.Aokuma:BAACLgAFFH8uAAIMAAkJTx7+AABuAwAMAAkJTx7+AABuAwAuAAQKfywAAwwACQlPJI8GACIDAAwACQlPJI8GACIDABEABAlSIRJIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn8oAAISAAgJug5SCgCRAQASAAgJug5SCgCRAQAAAA==.',
Aq='Aquaten:BAABLgAECn8jAAIGAAgJ9xVXFQD5AQAGAAgJ9xVXFQD5AQAAAA==.',
Ar='Aramac:BAAALgAECgEJAwAAAA==.Arashinigon:BAABLgAECn8ZAAMMAAkJhRAAawDxAAAMAAgJJg4AawDxAAARAAYJIBaJTgDPAAAAAA==.Arcafrost:BAAALgAECgkJAQAAAA==.Arceus:BAAALgAECgUJEQAAAA==.Archaon:BAABLgAECn8qAAMQAAgJkRD1WgCNAQAQAAgJkRD1WgCNAQATAAEJAADeUQAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgcJFgAUAHUUAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9GAAMUAAkJpib/AQBrAwAUAAkJpib/AQBrAwAVAAYJIyVeHwDlAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgkJEgAAAA==.Asmódeus:BAABLgAECn8cAAQWAAgJoQ73DQBTAQAWAAYJWw73DQBTAQAQAAgJCgoefQA/AQATAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
At='Atanker:BAAALgADCgMJBwAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAACLgAFFH8FAAIJAAIJxgeRpACIAAAJAAIJxgeRpACIAAAuAAQKfy0AAgkACQmhGQgtAGMCAAkACQmhGQgtAGMCAAAA.',
['Aì']='Aìo:BAABLgAECn8VAAMXAAYJJxXANQA/AQAXAAYJJxXANQA/AQAYAAQJvBZ4RQDyAAABLgAECgcJEwAZAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJCQABLgAECgkJFgAJAHIYAA==.Baelhay:BAABLgAECn8jAAIaAAgJHQVbKQDnAAAaAAgJHQVbKQDnAAAAAA==.Baelthas:BAAALgADCgcJDgAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belitha:BAACLgAFFH8KAAIFAAMJFiBrRwAOAQAFAAMJFiBrRwAOAQAuAAQKfy0AAgUACQlKIAsTAOgCAAUACQlKIAsTAOgCAAAA.Belmaris:BAABLgAECn8vAAISAAkJ7RyAAgCuAgASAAkJ7RyAAgCuAgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgUJBQAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8hAAIbAAgJaQyxfABoAQAbAAgJaQyxfABoAQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8aAAIMAAkJkxKdKQAFAgAMAAkJkxKdKQAFAgAAAA==.Bighunt:BAAALgAECgQJBAABLgAECgkJGgAMAJMSAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8eAAIEAAgJmw24JABPAQAEAAgJmw24JABPAQAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn86AAINAAgJvSGEAwCiAgANAAgJvSGEAwCiAgAAAA==.Blegh:BAACLgAFFH8OAAMcAAUJaRghKAAlAQAcAAUJGhYhKAAlAQAdAAEJlxXUDABLAAAuAAQKfyMAAx0ACQnCHqcKADECAB0ABwnHHqcKADECABwABwl/GygfAMoBAAAA.Blueflu:BAAALgAECgQJBAAAAA==.Bluegrass:BAABLgAECn9WAAIOAAkJvyTOAABfAwAOAAkJvyTOAABfAwAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMeAAgJxAnuRABkAQAeAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAAALgAFFAEJAQAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8gAAMKAAkJvRv1HQASAgAKAAkJvRv1HQASAgAPAAUJdxh5PgADAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAZAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAACLgAFFH8RAAIIAAQJrg81QgAkAQAIAAQJrg81QgAkAQAuAAQKfxcAAggACAmpEuBSAKcBAAgACAmpEuBSAKcBAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bulldogs:BAAALgADCgEJAQAAAA==.Bulova:BAAALgADCgEJAQAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAABLgAFFH8IAAIJAAYJUxfPTgBGAQAJAAYJUxfPTgBGAQABLgAFFAcJHQAfAN8eAA==.Bustedhoof:BAAALgADCgMJAwAAAA==.',
Ca='Caiphage:BAABLgAECn8kAAIFAAkJIxlCJwAsAgAFAAkJIxlCJwAsAgAAAA==.Caladelm:BAABLgAECn8XAAICAAcJphExkABQAQACAAcJphExkABQAQAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8lAAIbAAgJ2Q1fdQB3AQAbAAgJ2Q1fdQB3AQAAAA==.Carlarae:BAABLgAECn8WAAIJAAYJOQSF+wCwAAAJAAYJOQSF+wCwAAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8OAAIJAAQJih1NSwBOAQAJAAQJih1NSwBOAQAuAAQKfxwAAgkACQksIXATAOQCAAkACQksIXATAOQCAAAA.Cegeo:BAABLgAECn9IAAITAAkJihmkAwBUAgATAAkJihmkAwBUAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn9dAAMDAAkJnSOYBgD1AgADAAkJnSOYBgD1AgALAAEJ0g5qdgAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAACLgAFFH8GAAIQAAIJjhP4kgCXAAAQAAIJjhP4kgCXAAAuAAQKfyMAAxAABwncH0cyAA8CABAABwncH0cyAA8CABYABAlIGPISAP0AAAAA.Chìpotle:BAAALgAECgEJAgAAAA==.',
Ci='Ciennajewel:BAABLgAECn8XAAIgAAgJdRoSEwBBAgAgAAgJdRoSEwBBAgAAAA==.Cirdle:BAABLgAECn8tAAMIAAgJ0w8qVgCeAQAIAAgJ0w8qVgCeAQAHAAMJIwYLKwBnAAAAAA==.Cirona:BAABLgAECn8eAAIMAAcJjR82GgByAgAMAAcJjR82GgByAgAAAA==.',
Cl='Clausewitz:BAABLgAECn8ZAAIaAAkJ7gp3HgA9AQAaAAkJ7gp3HgA9AQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAACLgAFFH8GAAMQAAIJHBZFlACVAAAQAAIJHBZFlACVAAAWAAEJngaNKQBCAAAuAAQKfyAAAhAACQk+HJciAFUCABAACQk+HJciAFUCAAAA.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAZAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8hAAIVAAgJ7gLPWwDOAAAVAAgJ7gLPWwDOAAAAAA==.Creamtastic:BAAALgAECggJCAAAAA==.Creamyweamy:BAABLgAECn8gAAIgAAgJWRQgHwDIAQAgAAgJWRQgHwDIAQABLgAECggJCAAZAAAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA18qAArAQAJAAcJQA18qAArAQAhAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAAALgAECgUJCAAAAA==.Cruxsader:BAAALgAECgQJBQAAAA==.Cruzmaster:BAABLgAECn8eAAMVAAkJ6BQ9HQD2AQAVAAkJ6BQ9HQD2AQAiAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8pAAIJAAgJpAjlmQBDAQAJAAgJpAjlmQBDAQAAAA==.',
Cu='Cuddly:BAABLgAFFH8dAAIjAAcJfyEKBQDAAgAjAAcJfyEKBQDAAgABLgAFFAkJNQAYAD0jAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAFFAEJAQABLgAFFAgJKQAYAK8fAA==.',
Da='Daamass:BAAALgAECgEJAQAAAA==.Daddy:BAACLgAFFH8fAAIjAAcJ6yReBQC5AgAjAAcJ6yReBQC5AgAuAAQKf5IAAiMACQmzJgwAAAkEACMACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAZAAAAAA==.Daggonet:BAABLgAECn8eAAIbAAkJJyDGDQD8AgAbAAkJJyDGDQD8AgAAAA==.Dalrin:BAABLgAECn8XAAMiAAYJ7A+uFQBiAQAiAAYJ7A+uFQBiAQAVAAQJzAfqZwCjAAAAAA==.Darayia:BAAALgAECgEJAgAAAA==.Darkcarnival:BAABLgAECn8vAAIQAAkJQBqzHwBlAgAQAAkJQBqzHwBlAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkkill:BAAALgADCgEJAQABLgAFFAQJEQAeAIAbAA==.Darkknightx:BAACLgAFFH8KAAIDAAQJ1w2SJQAbAQADAAQJ1w2SJQAbAQAuAAQKfyEAAgMACQmJF0wsAAMCAAMACQmJF0wsAAMCAAAA.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAAALgAECgcJEgABLgAECggJGQAUANQOAA==.Darthraider:BAABLgAECn8cAAIbAAcJEA9SkQBBAQAbAAcJEA9SkQBBAQAAAA==.Dasnotgood:BAABLgAECn8ZAAMOAAcJuh2NDgDHAQAOAAYJUB+NDgDHAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8XAAQVAAgJxwdbSgAIAQAVAAgJxwdbSgAIAQAUAAEJowGnqgAhAAAiAAEJeAEORwAdAAAAAA==.Davrøs:BAAALgAECgQJCQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgAECgQJBAAAAA==.',
De='Deathspeaker:BAAALgADCgEJAQABLgAECggJJAAfABMTAA==.Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8ZAAIFAAkJyhQvNwDnAQAFAAkJyhQvNwDnAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAABLgAECn8bAAITAAcJ3ROEDgBSAQATAAcJ3ROEDgBSAQAAAA==.Dendreon:BAAALgADCgYJCQAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8qAAMgAAgJ+xEOKACCAQAgAAgJ+xEOKACCAQAXAAcJ3hA/MgBSAQAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8iAAIRAAkJAhW8HADfAQARAAkJAhW8HADfAQAAAA==.Desdemona:BAABLgAECn8oAAIBAAgJACEfCABUAgABAAgJACEfCABUAgAAAA==.Dethiaris:BAAALgAECgEJAwAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAACLgAFFH8KAAIIAAQJAA52RQAeAQAIAAQJAA52RQAeAQAuAAQKfxsAAwgACQlrGj8cAHgCAAgACQlrGj8cAHgCAAcAAglsA/lFABoAAAAA.',
Di='Dianimal:BAABLgAECn8iAAIRAAgJqAerPwAMAQARAAgJqAerPwAMAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJEgAZAAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAABLgAECn8sAAMeAAgJnCV6BABQAwAeAAgJnCV6BABQAwACAAgJmSK0GgCiAgAAAA==.',
Dk='Dklel:BAACLgAFFH8QAAIbAAUJ0CGlTgBPAQAbAAUJ0CGlTgBPAQAuAAQKf0AAAhsACQl4Jg4HAD0DABsACQl4Jg4HAD0DAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAACLgAFFH8IAAICAAMJIRKUZwDbAAACAAMJIRKUZwDbAAAuAAQKfyYAAwIACQkJFnA/ACgCAAIACQkJFnA/ACgCAAEABAl8AeZJAEAAAAAA.Doomfeather:BAAALgAECggJDAAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBKUcACMAQACAAkJIBKUcACMAQAAAA==.Dorow:BAAALgAECgEJAQAAAA==.',
Dr='Draaka:BAAALgAECgEJAQAAAA==.Dragee:BAAALgAECgEJBAABLgAECgkJGQAFAMoUAA==.Dragon:BAAALgAECgkJEAAAAA==.Dragonpunch:BAABLgAECn8qAAIjAAkJ6xmyHgAgAgAjAAkJ6xmyHgAgAgAAAA==.Driftyshaman:BAABLgAECn8nAAIVAAcJMgtiTAAAAQAVAAcJMgtiTAAAAQAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAABLgAECn8eAAIbAAgJ0wjikQBBAQAbAAgJ0wjikQBBAQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Du='Durnik:BAAALgAECgYJDAABLgAECggJIgAPAGkcAA==.',
Dw='Dworflundgrn:BAABLgAECn8tAAIiAAkJtA20EACkAQAiAAkJtA20EACkAQAAAA==.',
Dy='Dyamï:BAABLgAECn8xAAIjAAkJyx1+CAASAwAjAAkJyx1+CAASAwAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAABLgAECn8aAAIJAAkJzgUNkwBPAQAJAAkJzgUNkwBPAQAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8hAAIVAAgJXAqcRQAaAQAVAAgJXAqcRQAaAQAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAABLgAECn8ZAAIJAAcJBQ+4nQA8AQAJAAcJBQ+4nQA8AQAAAA==.Ellä:BAAALgAECgYJCQAAAA==.Elrythe:BAACLgAFFH8PAAIIAAQJGxM2PQAuAQAIAAQJGxM2PQAuAQAuAAQKfzgAAggACQmGIowJAAoDAAgACQmGIowJAAoDAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.',
Eu='Eukina:BAAALgAECgQJBQAAAA==.',
Ev='Evilmorana:BAAALgAECgMJBgAAAA==.',
Fa='Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAgABLgAECgkJFgAJAHIYAA==.Faye:BAAALgAECgEJAQAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAIMAAcJvhGOQwCAAQAMAAcJvhGOQwCAAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.Felrein:BAAALgADCgUJBQABLgAECgkJKQAaAPELAA==.',
Fi='Finegas:BAAALgAECgYJBgAAAA==.Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8hAAIiAAgJUBuaAABzAgAiAAgJUBuaAABzAgAuAAQKfyMAAiIACQnjJbUDAO8CACIACQnjJbUDAO8CAAAA.Floofndoom:BAAALgAFFAEJAQABLgAFFAgJIQAiAFAbAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAgJIQAiAFAbAA==.',
Fr='Fredrickk:BAABLgAECn8WAAMUAAcJdRQrPwCuAQAUAAcJdRQrPwCuAQAVAAQJWwoueQB/AAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAECgcJCQABLgAFFAUJEwAUAGUYAA==.Furryphase:BAACLgAFFH8TAAIUAAUJZRhkJABUAQAUAAUJZRhkJABUAQAuAAQKfyQAAxQACQnxHAwNALUCABQACQnxHAwNALUCABUABAlyCZF8AHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAgJIQAiAFAbAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
Fz='Fzoul:BAAALgAECgkJAQAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn85AAIUAAkJth5mEwCvAgAUAAkJth5mEwCvAgAAAA==.',
Go='Goatjira:BAAALgAECgQJCAAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Greygorypack:BAAALgADCgYJBQABLgADCgYJBQAZAAAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAlAGAgAA==.Gripisrdy:BAABLgAECn8vAAMbAAkJyR/SFADJAgAbAAkJyR/SFADJAgAmAAMJgRhONQDAAAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8hAAMnAAkJkyJBAQD1AgAnAAkJkyJBAQD1AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgkJCwAAAA==.Guìdo:BAABLgAECn8ZAAIUAAgJ1A62RwCMAQAUAAgJ1A62RwCMAQAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Habanero:BAAALgAECgEJAQAAAA==.Haggrd:BAABLgAECn8dAAICAAgJJh98JgBpAgACAAgJJh98JgBpAgAAAA==.Hairyjolene:BAABLgAECn8jAAIIAAgJERM1SADGAQAIAAgJERM1SADGAQAAAA==.Halleberries:BAAALgADCgYJBQAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAMJCAADADAWAA==.Handsome:BAAALgAFFAIJAwAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJEgAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAABLgAFFH8IAAIbAAQJxRI/ZgAoAQAbAAQJxRI/ZgAoAQAAAA==.',
Hi='Highlander:BAAALgAECgEJAgAAAA==.Hikaridh:BAABLgAFFH8DAAIFAAEJvxPPlwBAAAAFAAEJvxPPlwBAAAABLgAFFAkJLgAMAE8eAA==.Hikarimonk:BAABLgAFFH8RAAIjAAcJdRBOFQDMAQAjAAcJdRBOFQDMAQABLgAFFAkJLgAMAE8eAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAkJLgAMAE8eAA==.Hikarishaman:BAAALgAECgEJAQAAAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgUJEQAZAAAAAA==.Holyblimblam:BAAALgAECgYJEgAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8nAAMbAAgJBB4PRQDxAQAbAAgJmB0PRQDxAQAmAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIXAAYJNA38RQD2AAAXAAYJNA38RQD2AAAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Humper:BAAALgAECgMJAwAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.Huntley:BAAALgAECgQJBAAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icyjackets:BAABLgAECn8jAAMbAAgJtA9+dAB5AQAbAAgJtA9+dAB5AQAmAAQJpAWDRgBxAAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
Ih='Ihalo:BAAALgAECgEJAQAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJBgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA8iUgCpAQAIAAkJlA8iUgCpAQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBRfEJQDJAQADAAgJBRfEJQDJAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn8/AAMMAAgJ0Q+5PQCaAQAMAAgJ0Q+5PQCaAQARAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgcJEwAZAAAAAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAZAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIVAAYJfg6NWQDVAAAVAAYJfg6NWQDVAAAAAA==.Jessicà:BAAALgAECgQJBQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAwAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8lAAMUAAYJIhYRNgCrAQAUAAYJIhYRNgCrAQAVAAUJfBIZXADNAAAAAA==.Jiwà:BAABLgAFFH8HAAIUAAUJMgbzNgABAQAUAAUJMgbzNgABAQABLgAFFAUJEgAXAPkKAA==.Jiwâ:BAACLgAFFH8SAAIXAAUJ+QqSHgD5AAAXAAUJ+QqSHgD5AAAuAAQKfzkAAhcACQlGHrsMAIcCABcACQlGHrsMAIcCAAAA.Jiwå:BAAALgAECgYJBgAAAA==.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECggJEwAAAA==.Joss:BAAALgAFFAEJAgAAAA==.',
Ka='Kadan:BAAALgAECgYJCwABLgAFFAMJCgAFABYgAA==.Kahless:BAAALgADCgQJCQAAAA==.Kaibab:BAAALgADCgEJAgAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8gAAIDAAkJMAfwRQAuAQADAAkJMAfwRQAuAQAAAA==.Kaliyah:BAAALgADCgcJCQAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAAALgADCgkJFgAAAA==.Kavorkyan:BAAALgAECgcJCAAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Kerplaa:BAAALgAECgEJAQAAAA==.Keyadistor:BAABLgAECn8aAAMlAAkJYCBSEgBQAQAbAAYJ7hpDXQDbAQAlAAcJyB9SEgBQAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn9MAAIKAAkJKR4gCACwAgAKAAkJKR4gCACwAgAAAA==.',
Ki='Kiamara:BAABLgAECn8hAAIQAAgJ9QhVfgA8AQAQAAgJ9QhVfgA8AQAAAA==.Kinderlin:BAABLgAECn8jAAICAAYJtxQGqwAlAQACAAYJtxQGqwAlAQAAAA==.Kipo:BAAALgAECggJDwAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAIMAAcJbhaUNwC3AQAMAAcJbhaUNwC3AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgYJDgAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQdAAgJfRaSDwDiAQAdAAYJNhmSDwDiAQAcAAMJfRSEQgDYAAAfAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgcJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgAECgQJBAAAAA==.Lista:BAABLgAECn8XAAMYAAkJqiDmAwBdAwAYAAkJqiDmAwBdAwAXAAEJEgogjQAsAAABLgAECgkJQAAPAGclAA==.',
Lo='Loadedtater:BAABLgAECn9BAAQGAAkJpyVfAQBRAwAGAAkJDiVfAQBRAwAIAAgJlyaYDADsAgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Loralynn:BAACLgAFFH8RAAIMAAQJLgt3OADIAAAMAAQJLgt3OADIAAAuAAQKfxQAAgwABwn7FOk3ALYBAAwABwn7FOk3ALYBAAAA.Lorianne:BAACLgAFFH8HAAIUAAIJwRUgZwBtAAAUAAIJwRUgZwBtAAAuAAQKfygAAxQACAmvGGQpAOkBABQACAmvGGQpAOkBABUABQmxC7tWAOoAAAEuAAUUBAkRAAwALgsA.Lorri:BAAALgADCgQJBQABLgAFFAQJEQAMAC4LAA==.',
Lu='Lucianas:BAAALgAECggJEgAAAA==.Luckyfist:BAAALgAECgcJAQAAAA==.Lumindah:BAAALgAECgQJBAAAAA==.Lunchböx:BAAALgAECgMJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJEAAAAA==.',
Ly='Lysi:BAABLgAECn8jAAIIAAgJIh4gGgCFAgAIAAgJIh4gGgCFAgAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgAECgEJAQAAAA==.Madaea:BAABLgAECn8zAAIjAAkJqh/gCgDoAgAjAAkJqh/gCgDoAgAAAA==.Madameuyen:BAAALgADCgUJBQAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn9AAAIJAAkJHRxlHgCkAgAJAAkJHRxlHgCkAgABLgAFFAQJEwAGAB8bAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAABLgAECn8WAAIgAAcJSBzMEwA3AgAgAAcJSBzMEwA3AgABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx0nKwAuAgAIAAgJUx0nKwAuAgAAAA==.Makthamonk:BAAALgAECgMJAwABLgAECggJGAAIAFMdAA==.Malzeth:BAAALgAECgYJBgAAAA==.Marrilyn:BAAALgAFFAEJAwABLgAFFAcJCwAQAMQaAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn8zAAIIAAkJzyCdCwD1AgAIAAkJzyCdCwD1AgAAAA==.Mate:BAAALgAECgQJBwAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAECgcJCAAAAA==.Melbeast:BAABLgAECn8eAAIIAAgJ2htcLgAgAgAIAAgJ2htcLgAgAgAAAA==.Melorea:BAAALgAECgQJBgAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxAzWwDKAQAJAAkJNhAzWwDKAQAhAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8gAAMTAAgJpQniFAACAQATAAgJpQniFAACAQAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgADCgkJHAAAAA==.Mignon:BAAALgAECgMJBgAAAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJCgAAAA==.Missiah:BAABLgAECn89AAIBAAkJcQRIJgDhAAABAAkJcQRIJgDhAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgUJCQAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Molfise:BAABLgAECn8pAAMKAAgJ0B5VDABvAgAKAAgJ7x1VDABvAgAPAAQJpRHfRwD1AAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8/AAIgAAkJ4B9qBgAKAwAgAAkJ4B9qBgAKAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAABLgAECn8eAAMLAAgJ8AXUOADeAAALAAgJ8AXUOADeAAAaAAIJaAHKUwAuAAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgEJAQAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEAAZAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECgkJIAAeAEYMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAjAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgaRsgAbAQAJAAgJBgaRsgAbAQAAAA==.',
Na='Nachtelf:BAABLgAECn9eAAIIAAkJFSJVBwAiAwAIAAkJFSJVBwAiAwAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannydo:BAAALgADCgkJEQABLgAECgkJFgAUAFYTAA==.Nannysham:BAABLgAECn8WAAIUAAkJVhOXLAADAgAUAAkJVhOXLAADAgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAABLgAECn9UAAIJAAkJqyTGBQBUAwAJAAkJqyTGBQBUAwAAAA==.Nathel:BAAALgAECgcJBwAAAA==.Natherel:BAABLgAECn8YAAQLAAgJ2QRzQADBAAALAAcJVgVzQADBAAADAAUJ5gMUfACBAAAaAAEJ5QERWgAgAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8SAAMfAAUJPBPlFQAvAQAfAAQJSRblFQAvAQAcAAQJmAthRACwAAAuAAQKfx0AAx8ACAnZFPsNAOwBAB8ABwnWFvsNAOwBABwABwm5GFQoAKEBAAEuAAUUCAkpABgArx8A.',
Ne='Newander:BAABLgAECn80AAIMAAkJaRMELQDxAQAMAAkJaRMELQDxAQABLgAECggJIgAPAGkcAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJEAAAAA==.Nirra:BAAALgAECgQJCgAAAA==.',
No='Nonphatmilk:BAAALgAECgcJDgAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMbAAkJmxJwUADQAQAbAAkJmxJwUADQAQAmAAEJGxJ6RQAyAAAAAA==.Novatron:BAAALgADCgIJAgAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR8bTAD1AQAJAAgJCR8bTAD1AQAAAA==.',
Og='Ograskygazer:BAABLgAECn8dAAIMAAgJcgZ8agDzAAAMAAgJcgZ8agDzAAAAAA==.',
Om='Omee:BAABLgAECn8jAAMEAAkJVxqhDwAqAgAEAAkJVxqhDwAqAgAFAAYJ+QvBigAIAQAAAA==.Omy:BAABLgAECn8vAAIJAAcJ4w4jlgBKAQAJAAcJ4w4jlgBKAQAAAA==.',
Op='Ophela:BAAALgAECgMJBAAAAA==.',
Or='Orakio:BAABLgAFFH8GAAIbAAIJvQ+G2wCEAAAbAAIJvQ+G2wCEAAABLgAFFAQJFAAJAGoXAA==.Oralena:BAABLgAECn8jAAIIAAgJXgikcwBVAQAIAAgJXgikcwBVAQAAAA==.Orioncheats:BAABLgAECn9BAAIbAAkJzxvqKgBTAgAbAAkJzxvqKgBTAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAZAAAAAA==.',
Ox='Oxygën:BAABLgAECn8dAAIJAAgJaAXItgAVAQAJAAgJaAXItgAVAQAAAA==.',
Pa='Paladingbat:BAACLgAFFH8RAAIeAAQJgBvQHAAyAQAeAAQJgBvQHAAyAQAuAAQKfxwAAh4ACAnfItMHAA0DAB4ACAnfItMHAA0DAAAA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAZAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgcJEwAAAA==.',
Pe='Ped:BAABLgAECn9HAAMPAAkJQR96CAC9AgAPAAkJQR96CAC9AgAjAAEJ2AHbdgAXAAAAAA==.Peon:BAABLgAECn8UAAIDAAcJKxqqIgDdAQADAAcJKxqqIgDdAQAAAA==.',
Ph='Pharune:BAABLgAECn8vAAIkAAkJFRKhFQCjAQAkAAkJFRKhFQCjAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8tAAIJAAkJoBa1OAAzAgAJAAkJoBa1OAAzAgAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAQJDgAVAIwcAA==.Picklebob:BAAALgAECggJCAABLgAFFAQJDgAVAIwcAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAQJDgAVAIwcAA==.Picklebosh:BAABLgAFFH8OAAIVAAQJjBz6GABMAQAVAAQJjBz6GABMAQAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgYJCAABLgAECgkJFgAJAHIYAA==.Ponky:BAABLgAECn8cAAIXAAkJKhG1KQCCAQAXAAkJKhG1KQCCAQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8MAAIMAAMJghQoQQCpAAAMAAMJghQoQQCpAAABLgAFFAkJNQAYAD0jAA==.',
Pr='Precious:BAACLgAFFH8bAAIYAAcJbxXBDQA3AgAYAAcJbxXBDQA3AgAuAAQKf0QABBgACQkjJHUDAGwDABgACQkjJHUDAGwDACAABglwDxs2AGQBABcABAkvE7FWALYAAAEuAAUUCAkpABgArx8A.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKQAaAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIdAAkJXgttEAABAQAdAAkJXgttEAABAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Qw='Qweyqway:BAAALgADCggJCAAAAA==.',
Ra='Racecar:BAACLgAFFH8FAAIDAAMJ1wwFNwDSAAADAAMJ1wwFNwDSAAAuAAQKfzoAAwMACAkVHtASAFwCAAMACAn4HdASAFwCAAsAAQmKFWlxADsAAAAA.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8iAAMPAAgJaRw1EgAtAgAPAAgJaRw1EgAtAgAjAAIJpw0bnQBYAAAAAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ramaloce:BAAALgAECgQJBAAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8rAAIgAAgJZRDvJQCTAQAgAAgJZRDvJQCTAQAAAA==.Raziel:BAAALgADCgkJCQAAAA==.',
Re='Redbeard:BAAALgAECgEJAQAAAA==.Rehum:BAABLgAECn8UAAICAAYJPgh38QDHAAACAAYJPgh38QDHAAAAAA==.Remagtrepxe:BAAALgAECgEJAQABLgAECgcJJwAVADILAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCwAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8sAAMiAAkJgRCxFABuAQAiAAcJdhOxFABuAQAUAAYJ3gdGjQC7AAAAAA==.Revèndreth:BAAALgAECgQJBQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgQJBAAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn9LAAIXAAkJChW0FwAKAgAXAAkJChW0FwAKAgAAAA==.Ricengravy:BAAALgADCgEJAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAABLgAECn8XAAIIAAYJlwshcAAXAQAIAAYJlwshcAAXAQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMbAAkJERu6QAD/AQAbAAkJ5xq6QAD/AQAlAAYJrhWxCABaAQAAAA==.Rockywarlock:BAAALgAECgkJDAAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8jAAIdAAgJFg93CgB0AQAdAAgJFg93CgB0AQAAAA==.Roryn:BAACLgAFFH8IAAICAAMJoRQTawDVAAACAAMJoRQTawDVAAAuAAQKf1oAAgIACQlWJkwBAIQDAAIACQlWJkwBAIQDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAABLgAFFH8IAAIDAAMJfBltLgDyAAADAAMJfBltLgDyAAAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAgJMwAMACIiAA==.Rugiia:BAACLgAFFH8zAAIMAAgJIiIXAgAoAwAMAAgJIiIXAgAoAwAuAAQKf0YAAwwACQmWJkEAAOMDAAwACQmWJkEAAOMDAA4ABAlfJTkbAC4BAAAA.Rugiian:BAABLgAFFH8KAAIjAAUJmBs7GwCPAQAjAAUJmBs7GwCPAQABLgAFFAgJMwAMACIiAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8aAAIQAAkJjQnJYwB3AQAQAAkJjQnJYwB3AQAAAA==.Ryuka:BAABLgAECn8iAAIkAAkJAgoAKAAUAQAkAAkJAgoAKAAUAQAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Sabyne:BAAALgAECgEJAQABLgAECgYJEQAZAAAAAA==.Samyria:BAABLgAECn8VAAIIAAYJ+Q5wjgAfAQAIAAYJ+Q5wjgAfAQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8oAAQjAAkJFwwSPwBtAQAjAAkJFwwSPwBtAQAPAAcJlg4BOwATAQAKAAEJgAH5mQAYAAAAAA==.Saucy:BAABLgAECn8XAAMVAAgJeyA9DQCSAgAVAAgJeyA9DQCSAgAiAAEJAAA7SQAAAAAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAZAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8wAAIgAAkJaBWKFAAwAgAgAAkJaBWKFAAwAgAAAA==.Selati:BAAALgADCgMJAwAAAA==.Seric:BAABLgAECn8pAAMaAAkJ8Qv7HABLAQAaAAkJ8Qv7HABLAQADAAQJugSKhgBkAAAAAA==.Sesethi:BAAALgAECgMJAwABLgAECggJHgAQAAQfAA==.',
Sh='Shadowdancèr:BAABLgAECn8gAAMXAAgJwhalHQDYAQAXAAgJwhalHQDYAQAYAAMJ+REsUgC3AAAAAA==.Shadowlocke:BAAALgAECgUJBQAAAA==.Shadowyisis:BAABLgAECn8VAAIXAAkJyBSaFgAVAgAXAAkJyBSaFgAVAgAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamoochies:BAAALgAECgEJAQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8TAAIGAAQJHxtsDwBGAQAGAAQJHxtsDwBGAQAuAAQKf0QAAwYACQnQI2ACACQDAAYACQm3I2ACACQDAAcABwnWHTkbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAUJFwABAIgPAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAYJFwAaAL4WAA==.Skybox:BAAALgAECgUJCAAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMYAAYJvhFAMAAeAQAYAAUJiBBAMAAeAQAgAAUJfQ8sUwCNAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgkJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAACLgAFFH8IAAIJAAMJbgOGkAC2AAAJAAMJbgOGkAC2AAAuAAQKfzMAAgkACQmtEipGAAYCAAkACQmtEipGAAYCAAAA.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8gAAQeAAkJRgwnLwCeAQAeAAkJRgwnLwCeAQABAAYJQBM8KgDFAAACAAEJYBYWgAE6AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAZAAAAAA==.Splashdaddy:BAACLgAFFH8UAAIUAAQJgCSgGQCTAQAUAAQJgCSgGQCTAQAuAAQKfyQAAhQACQlGJHQHADYDABQACQlGJHQHADYDAAEuAAUUAQkBABkAAAAA.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgYJDAAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn8pAAIUAAgJzQflZQAmAQAUAAgJzQflZQAmAQAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgAECgYJDQAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Summonme:BAAALgAECgcJCAAAAA==.Sunless:BAAALgAECgIJBAAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylamor:BAAALgAECgcJBwAAAA==.Sylvancura:BAAALgAECgUJCAAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn8qAAIkAAgJOCHpBgCIAgAkAAgJOCHpBgCIAgAAAA==.',
Ta='Taea:BAAALgAECgcJCgABLgAECgcJHgAMAI0fAA==.Taeus:BAACLgAFFH8UAAIJAAQJahcPUQBBAQAJAAQJahcPUQBBAQAuAAQKfxkAAgkACQkiGeBeAB4CAAkACQkiGeBeAB4CAAAA.Taintedcure:BAAALgADCgkJEgAAAA==.Taintedkoma:BAAALgAECggJCwABLgAECggJIAATAKUJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAABLgAECn8YAAIFAAcJKQVHrQDJAAAFAAcJKQVHrQDJAAAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIaAAkJoiEKCAClAgAaAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8tAAIIAAgJ/AEZ0QCjAAAIAAgJ/AEZ0QCjAAAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Tellwyrn:BAAALgAECgQJBQAAAA==.Temajin:BAABLgAECn8YAAMeAAYJrgtUSgASAQAeAAYJrgtUSgASAQACAAIJvwu8nQEtAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAABLgAECn8dAAMfAAgJ+CHYBADTAgAfAAgJ+CHYBADTAgAcAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgQJBgAAAA==.',
Th='Thavis:BAABLgAECn8WAAMQAAcJEA8+lgARAQAQAAcJQgw+lgARAQATAAEJChZXOQBAAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn88AAIIAAgJICKREgC6AgAIAAgJICKREgC6AgAAAA==.Thetimelord:BAAALgAECgUJBwAAAA==.Thewarrior:BAABLgAECn8VAAIDAAgJLyOsDACgAgADAAgJLyOsDACgAgAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8mAAICAAgJVhXNSwD/AQACAAgJVhXNSwD/AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJCQABLgAECgkJHgAVAFQVAA==.Torrey:BAABLgAECn9EAAINAAkJRhHgCgCtAQANAAkJRhHgCgCtAQAAAA==.',
Tr='Tradd:BAACLgAFFH8MAAIYAAMJVhwdKAAFAQAYAAMJVhwdKAAFAQAuAAQKfyEAAhgACQmLHnUJANoCABgACQmLHnUJANoCAAAA.Trigg:BAAALgAECgUJBQABLgAFFAMJCgAFABYgAA==.Tristyana:BAABLgAECn9aAAIIAAkJdB6xDwDQAgAIAAkJdB6xDwDQAgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn9AAAQPAAkJZyXbAgA5AwAPAAkJZyXbAgA5AwAjAAcJgxZEIwCZAQAKAAcJhBEGLQBRAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJQAAPAGclAA==.',
Ty='Tylurien:BAABLgAECn8pAAIeAAkJkyCKBwASAwAeAAkJkyCKBwASAwAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Uk='Ukon:BAAALgAECgkJCQAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn84AAITAAgJlQ7lDgBNAQATAAgJlQ7lDgBNAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valeris:BAAALgAECgYJBwAAAA==.Valkoinen:BAABLgAECn9RAAIfAAgJFwxAFwBZAQAfAAgJFwxAFwBZAQAAAA==.Valora:BAABLgAECn9aAAQYAAkJlB7lDACeAgAYAAkJIBzlDACeAgAXAAkJOBWAEwA1AgAgAAcJYx0sIQC2AQAAAA==.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8bAAIMAAgJYQakbwDkAAAMAAgJYQakbwDkAAAAAA==.Vargen:BAABLgAECn8hAAIoAAgJYBhmGADVAQAoAAgJYBhmGADVAQAAAA==.Varonika:BAABLgAECn8WAAITAAUJIwNWLQBhAAATAAUJIwNWLQBhAAAAAA==.Vayla:BAABLgAECn8zAAIaAAkJ3hvxCABmAgAaAAkJ3hvxCABmAgAAAA==.',
Ve='Vee:BAAALgAECgQJCAABLgAECgkJGQAFAMoUAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJwAbAAQeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn8xAAICAAgJXQzvjwBQAQACAAgJXQzvjwBQAQAAAA==.',
Vo='Voidofdeath:BAAALgAECgYJEAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn9JAAIMAAkJTAOqawDvAAAMAAkJTAOqawDvAAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBQAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjwwihgDQAAAJAAMJjwwihgDQAAAuAAQKfyoAAgkACQk+H4AdAKkCAAkACQk+H4AdAKkCAAAA.Wargrimm:BAABLgAECn8uAAIVAAkJyR4PCwCvAgAVAAkJyR4PCwCvAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8UAAIeAAQJISbcEgCTAQAeAAQJISbcEgCTAQAuAAQKf3AAAx4ACQnQJhIAAPgDAB4ACQnQJhIAAPgDAAIACQktI68GADoDAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJHQARAO4WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJHQARAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJHQARAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJHQARAO4WAA==.Whisperz:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Whizpa:BAABLgAECn8dAAIRAAkJ7hZqFwAPAgARAAkJ7hZqFwAPAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJHQARAO4WAA==.',
Wi='Wickerchickn:BAABLgAECn8ZAAIkAAkJThSEFgCbAQAkAAkJThSEFgCbAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJHQARAO4WAA==.Wilshammy:BAAALgAECgUJCwAAAA==.Wispy:BAABLgAECn8fAAIVAAcJAxPkNQBgAQAVAAcJAxPkNQBgAQAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAABLgAECn8VAAMIAAkJXBTuMwAKAgAIAAkJXBTuMwAKAgAGAAEJ6wa3ZQAxAAAAAA==.Wrathbourne:BAAALgAECgYJEgABLgAECgkJFQAIAFwUAA==.Wrathchoi:BAAALgAECgYJDAAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJFQAIAFwUAA==.',
Xa='Xantchaa:BAAALgAECgEJAQABLgAECgkJGgAJAI0bAA==.Xaquandrel:BAACLgAFFH8IAAIDAAMJMBaIMADpAAADAAMJMBaIMADpAAAuAAQKfzUAAgMACQkgGosSAF4CAAMACQkgGosSAF4CAAAA.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8sAAMIAAgJJh+SMwDhAQAIAAgJOR2SMwDhAQAGAAYJxB98HgCpAQAAAA==.Xilo:BAAALgAECgkJEAAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAZAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAFFAMJBAAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEwAAAA==.',
Yu='Yuriko:BAAALgAECgEJAQAAAA==.',
Yz='Yzaak:BAAALgAECgMJAwAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAABLgAECn8aAAIJAAkJjRsONABGAgAJAAkJjRsONABGAgAAAA==.Zenicks:BAAALgADCgYJBgABLgAECggJUQAfABcMAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAZAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAABLgAECn8UAAImAAcJcSDtDQAqAgAmAAcJcSDtDQAqAgAAAA==.',
Zu='Zurazaee:BAABLgAECn8jAAIgAAgJMhn0EgBCAgAgAAgJMhn0EgBCAgAAAA==.',
['Zî']='Zîth:BAAALgADCgkJCQAAAA==.',
['År']='Årtêmis:BAAALgAECgkJEgAAAA==.',
['Él']='Élle:BAAALgAFFAEJAQAAAA==.',
['Ér']='Éric:BAABLgAECn9dAAIkAAkJphw+BgCaAgAkAAkJphw+BgCaAgAAAA==.',
['Ïr']='Ïridescent:BAAALgAECgQJBAAAAA==.',
['Ði']='Ðiabloist:BAAALgADCgMJAwAAAA==.',
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
