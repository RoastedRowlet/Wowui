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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Mage-Frost','Hunter-Marksmanship','Unknown-Unknown','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Priest-Discipline','Priest-Shadow','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Mage-Arcane','Druid-Guardian','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Druid-Feral','Priest-Holy','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Rogue-Subtlety','Monk-Brewmaster','Paladin-Retribution','Hunter-Survival','Paladin-Holy','DeathKnight-Frost','DemonHunter-Vengeance','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAABLgAECn8aAAMBAAgJEQylSwBMAQABAAgJEQylSwBMAQACAAEJKAV/lAAmAAAAAA==.Aaramis:BAACLgAFFH8IAAIBAAMJ+wtSPQC6AAABAAMJ+wtSPQC6AAAuAAQKfy8AAgEACAkcFAQ9AIgBAAEACAkcFAQ9AIgBAAAA.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ac='Achin:BAAALgADCgUJBQAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAABLgAECn8UAAIDAAgJEwQcqQASAQADAAgJEwQcqQASAQAAAA==.',
Ag='Aggrodk:BAAALgAECgIJAgAAAA==.',
Ah='Ahchu:BAAALgAECgIJAgAAAA==.Ahiru:BAAALgAECgMJAwAAAA==.',
Ai='Aidoffhealer:BAAALgAECgUJCwAAAA==.',
Al='Alariah:BAAALgAFFAEJAQAAAQ==.Alaín:BAABLgAECn8jAAIEAAgJuBiMCQC0AQAEAAgJuBiMCQC0AQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgAFAAAAAA==.Aldoraline:BAAALgADCgIJAwAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQABLgAECgEJAgAFAAAAAA==.Alystair:BAAALgADCgQJCAABLgAECggJGgAGAEAeAA==.',
Am='Ambellina:BAAALgAECgQJBQAAAA==.Ampse:BAAALgAECgUJCAAAAA==.Amzy:BAAALgADCgYJCQABLgAECgEJAQAFAAAAAA==.',
An='Anaria:BAAALgAECgQJCQAAAA==.Angbu:BAABLgAECn8iAAMHAAcJQRcrEABzAQAHAAcJQRcrEABzAQACAAEJoARgkQAmAAAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Aphadiri:BAAALgAECgMJBAAAAA==.Apinkninja:BAABLgAECn8nAAIDAAcJGxqmYQCfAQADAAcJGxqmYQCfAQAAAA==.',
Ar='Aranyssa:BAABLgAECn8hAAQIAAkJ1h+oBwC+AQAIAAYJhSCoBwC+AQAJAAYJ3hGzmQDzAAAKAAQJLhq2GwCoAAAAAA==.Arch:BAAALgAECgIJAgABLgAFFAUJFgAJAI4kAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAABLgAFFH8JAAILAAMJAQvhKgDMAAALAAMJAQvhKgDMAAAAAA==.Ardur:BAAALgAECgMJAwAAAA==.Arnøld:BAAALgAFFAIJAgAAAA==.Arruna:BAAALgAECgYJEQAAAA==.Artorìas:BAAALgADCgkJCwABLgAECggJGgAGAEAeAA==.',
As='Asham:BAABLgAECn8sAAMMAAgJOQ3WJAB5AQAMAAgJOQ3WJAB5AQANAAEJ0hDAawA3AAAAAA==.Ashenbloom:BAABLgAECn8hAAIOAAgJigkjUwAgAQAOAAgJigkjUwAgAQAAAA==.Asiago:BAABLgAECn8XAAMPAAkJ4BIgLQBYAQAPAAkJ4BIgLQBYAQAQAAEJRge0PwAxAAAAAA==.Aspect:BAABLgAECn8aAAMGAAgJQB6QAQBUAgAGAAgJQB6QAQBUAgADAAEJWRLEYAE/AAAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgAECgQJBQAAAA==.',
Av='Avacúma:BAAALgAECgIJAwAAAA==.Avvalethra:BAABLgAECn87AAMRAAkJKh0DEQCgAgARAAkJKh0DEQCgAgAEAAgJqg3XOwBwAQAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgcJDAAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAcJGAAPAOIdAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Babyball:BAAALgAECgYJCgAAAA==.Bachshots:BAABLgAFFH8IAAIRAAQJcQrmMQAbAQARAAQJcQrmMQAbAQAAAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgYJDgAAAA==.Bainey:BAAALgADCgIJAgABLgADCgYJCwAFAAAAAA==.Bananataffy:BAABLgAECn8UAAIOAAYJjhWZPAB/AQAOAAYJjhWZPAB/AQAAAA==.Barackoshama:BAABLgAECn8eAAICAAkJAxzJGADwAQACAAkJAxzJGADwAQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Basedween:BAAALgADCgcJGAAAAA==.Battlescars:BAAALgAFFAIJAgAAAA==.Baw:BAABLgAECn84AAMDAAkJ1xzgGgCfAgADAAkJ1xzgGgCfAgASAAMJFwmTFQBvAAAAAA==.',
Be='Bearelf:BAAALgADCgIJAgAAAA==.Bearlinwall:BAABLgAECn8YAAITAAYJFxC4JwDTAAATAAYJFxC4JwDTAAAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.Bews:BAAALgAECgUJBAAAAA==.',
Bi='Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigdumbo:BAAALgAECgQJBQABLgAFFAMJBQABAOwbAA==.Bigskydh:BAAALgAECgYJEAAAAA==.Bigskymage:BAAALgAECgUJDgAAAA==.Billybones:BAAALgAECgMJBAAAAA==.Bip:BAAALgADCgEJAQAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAFFAEJAQAFAAAAAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECggJJQAUAH4MAA==.Bladedozzer:BAAALgAECgYJCAAAAA==.Blindinglite:BAACLgAFFH8FAAIVAAMJORYfEADrAAAVAAMJORYfEADrAAAuAAQKfyQAAhUABwkWIyYOAIICABUABwkWIyYOAIICAAAA.Blindtoast:BAAALgAECgIJAgAAAA==.Blkpriest:BAAALgAECgIJAwAAAA==.Bloodhaze:BAACLgAFFH8KAAIVAAMJLh/RDgD8AAAVAAMJLh/RDgD8AAAuAAQKfyAAAhUACQmjHxgLAK8CABUACQmjHxgLAK8CAAAA.Blorp:BAACLgAFFH8QAAIWAAMJIBb8RwDhAAAWAAMJIBb8RwDhAAAuAAQKfxwAAhYACAnfHMwlAHACABYACAnfHMwlAHACAAAA.',
Bo='Bodizzle:BAAALgAECgEJAgAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgQJCAAAAA==.Borestus:BAAALgAECgYJDAAAAA==.Bouldur:BAABLgAECn8ZAAQLAAYJvgptSgDzAAALAAYJKgltSgDzAAAXAAQJLAhoPQCcAAAYAAEJzgIBUgAYAAAAAA==.Bownystark:BAABLgAECn8eAAIEAAcJCCJHFQCIAgAEAAcJCCJHFQCIAgAAAA==.Bozz:BAAALgAECgQJBQAAAA==.',
Br='Brickingit:BAAALgAECgYJCwAAAA==.Brieter:BAAALgAECgcJDAABLgAECgkJFwAPAOASAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokendrako:BAAALgAFFAQJBAAAAA==.Brokikobo:BAAALgADCggJCwAAAA==.Broly:BAAALgAECgEJAQAAAA==.Bromthelian:BAAALgADCgkJCQABLgAECgYJEQAFAAAAAA==.Broughston:BAAALgAECgEJAQAAAA==.Brutusx:BAABLgAECn8aAAIRAAYJ3QvyggAJAQARAAYJ3QvyggAJAQAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAABLgAECn8dAAMTAAgJ8BwRCAA4AgATAAgJ8BwRCAA4AgAZAAMJwQRwMQBaAAAAAA==.Burntcring:BAAALgAECgUJCgAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJDgAAAA==.',
Bx='Bxxberry:BAAALgAECgQJDAAAAA==.',
Ca='Camipriest:BAAALgAECgEJAQAAAA==.Carllina:BAAALgAECgYJBgAAAA==.Carmane:BAAALgAECgUJBQAAAA==.Casstyelle:BAAALgAECgQJBgABLgAECggJGgAIACkTAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgUJCgABLgAECgkJIQAIANYfAA==.Cet:BAAALgAECgQJBAABLgAECggJGgAGAEAeAA==.Cexiback:BAAALgAECgUJCgAAAA==.',
Ch='Chairon:BAAALgAECgQJBAABLgAECgUJEAAFAAAAAA==.Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheesus:BAAALgAECgcJDAABLgAECgkJFwAPAOASAA==.Chicharon:BAAALgAECgUJDwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECggJGwAaANgdAA==.Chipsnsalsa:BAAALgAECgQJBAABLgAECggJGwAaANgdAA==.Chocoriffic:BAABLgAECn8bAAIaAAgJ2B1IDAB7AgAaAAgJ2B1IDAB7AgAAAA==.Chokoballs:BAAALgAECgEJAQABLgAECgkJNAAbAHwYAA==.Chokoballz:BAAALgAECggJEwABLgAECgkJNAAbAHwYAA==.Churva:BAAALgADCgkJCQABLgAECgkJGgAWAHwJAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAABLgAECn8sAAITAAkJ9B4iAwDWAgATAAkJ9B4iAwDWAgABLgAECgkJHAARACcgAA==.Coldbrewz:BAAALgAECgYJDwAAAA==.Condensation:BAAALgADCgEJAQAAAA==.Coopah:BAAALgAECgkJBQAAAA==.Corgibutts:BAAALgAECgYJCQAAAA==.Corvyr:BAAALgADCgkJCQAAAA==.',
Cr='Crackjones:BAAALgAECgYJBAAAAA==.Crapsrocks:BAAALgAECgQJBAAAAA==.Crazydave:BAABLgAECn8aAAIaAAkJ7xEoIwDMAQAaAAkJ7xEoIwDMAQAAAA==.Creemywitchu:BAAALgADCgEJAQABLgADCgcJBwAFAAAAAA==.Crisgmt:BAAALgAECgcJDQAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAAALgAFFAEJAQAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Cryptìc:BAACLgAFFH8KAAINAAYJjhkuBgC+AQANAAYJjhkuBgC+AQAuAAQKfx4AAg0ACAmPI70HALYCAA0ACAmPI70HALYCAAEuAAUUBgkXAAMABRkA.Cryptîc:BAACLgAFFH8XAAIDAAYJBRnwGgC6AQADAAYJBRnwGgC6AQAuAAQKfzAAAgMACAnSJRoTAM0CAAMACAnSJRoTAM0CAAAA.Cráckjones:BAAALgADCgEJAQAAAA==.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8YAAIDAAcJjxlOXwAdAgADAAcJjxlOXwAdAgAAAA==.Dabbia:BAACLgAFFH8GAAMIAAQJRxFyCQCYAAAJAAMJMgwWZgDLAAAIAAIJQBNyCQCYAAAuAAQKfyQABAoACAn7HAkTALMBAAkABgl4G5JXAMEBAAoABgnlGgkTALMBAAgABgntHIgIAKoBAAAA.Daedleus:BAAALgADCgQJBAAAAA==.Damented:BAABLgAECn8aAAMIAAgJKRO5CgB9AQAIAAgJKRO5CgB9AQAJAAMJyw/cwwCnAAAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnchild:BAAALgADCgEJAQABLgAECgYJHgABALMSAA==.Dawnpaw:BAABLgAECn8iAAMcAAkJqhNaIgCgAQAcAAgJcxFaIgCgAQAdAAUJpBXaNwD2AAAAAA==.Daymonesus:BAAALgAECgUJBQAAAA==.',
De='Deathballz:BAABLgAECn80AAIbAAkJfBjxLQAkAgAbAAkJfBjxLQAkAgAAAA==.Deathsbreach:BAABLgAECn8VAAIWAAYJ4w8lfgD8AAAWAAYJ4w8lfgD8AAAAAA==.Deathsmite:BAAALgAECgIJBAAAAA==.Deathtee:BAABLgAECn8YAAIbAAgJrxxPRgAiAgAbAAgJrxxPRgAiAgAAAA==.Deepwaters:BAAALgADCgcJDgAAAA==.Dekuslice:BAABLgAECn8bAAIeAAYJbhTgMgAeAQAeAAYJbhTgMgAeAQAAAA==.Delafant:BAAALgAECgYJCwAAAA==.Deldaris:BAAALgAECgMJAwAAAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonarc:BAAALgAECgYJBgAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Derpyderp:BAAALgAECgEJAQABLgAECgkJFAADALoMAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgAFAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAAALgADCgcJCAAAAA==.',
Di='Diatomaceous:BAAALgADCgEJAQAAAA==.Dinkys:BAAALgADCgYJCwABLgAECgYJDwAFAAAAAA==.Dinsum:BAAALgADCgcJFAAAAA==.Diogenist:BAAALgAECgUJCgAAAA==.Dirtydhunter:BAAALgAECgYJBgAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAAALgAECgYJCgABLgAFFAMJCAAfAOskAA==.',
Do='Dogdad:BAAALgADCgcJCwAAAA==.Doktardoodad:BAAALgAECgYJCwAAAA==.Doktartides:BAAALgAECgEJAQAAAA==.Doktarzen:BAAALgAECgQJBgAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Donut:BAAALgAECgUJBQAAAA==.Doomslayer:BAABLgAECn8aAAIWAAkJfAn0YgB4AQAWAAkJfAn0YgB4AQAAAA==.Doresearch:BAABLgAECn8iAAICAAgJkBXWJQCOAQACAAgJkBXWJQCOAQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAABLgAECn8ZAAIJAAgJSh/+NADsAQAJAAgJSh/+NADsAQAAAA==.Dragontee:BAAALgADCgQJBAABLgAECggJGAAbAK8cAA==.Drakarys:BAAALgAECgYJCwAAAA==.Drakex:BAAALgAECgUJBwAAAA==.Drakoswrath:BAAALgAECgUJBgAAAA==.Dreamyskull:BAAALgADCgQJAgAAAA==.Drengist:BAABLgAECn8zAAIgAAkJhRoPDABVAgAgAAkJhRoPDABVAgAAAA==.Drexybear:BAABLgAECn8hAAMRAAgJpCGyGABpAgARAAgJdCGyGABpAgAEAAYJmR4KCQDAAQAAAA==.Drezbi:BAAALgAECgUJEwAAAA==.Drpally:BAAALgADCgEJAQAAAA==.Drpebbles:BAAALgAECgQJCwAAAA==.Druidskillz:BAAALgADCgEJAQAAAA==.',
Du='Dulcineru:BAAALgADCgYJCgAAAA==.Dunbarth:BAABLgAECn8jAAIhAAkJbg00ZgCDAQAhAAkJbg00ZgCDAQAAAA==.Durzaman:BAAALgAECgYJDQAAAA==.Durzuk:BAAALgAECgMJAwAAAA==.Duskhoof:BAAALgADCgIJAwAAAA==.',
Dy='Dynastyy:BAAALgAECgkJBwAAAA==.',
['Dé']='Dévílyñ:BAAALgAECgYJEwAAAA==.',
['Dü']='Dük:BAABLgAECn8YAAMJAAcJjxEuhgAYAQAJAAYJMRIuhgAYAQAKAAIJZA5RTACIAAAAAA==.',
Ed='Eddai:BAAALgAECgEJAQAAAA==.',
Ef='Eff:BAAALgAECgIJAgAAAA==.',
Eg='Eggy:BAAALgAECgkJDgAAAA==.',
Ek='Eks:BAAALgADCgkJGQAAAA==.',
El='Eldraaqeyn:BAAALgAECgMJAwAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elishii:BAAALgADCgYJBgAAAA==.Elkanàh:BAAALgAFFAEJAgABLgAFFAMJCAAMAMIgAA==.Elleynle:BAAALgAECgUJEAAAAA==.Elunara:BAACLgAFFH8UAAITAAQJ+hdYBwAuAQATAAQJ+hdYBwAuAQAuAAQKfz4AAhMACQkHIG8CAO8CABMACQkHIG8CAO8CAAEuAAQKCQkhAAgA1h8A.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.Emptor:BAAALgADCgEJAQAAAA==.Emreezus:BAAALgAECgMJAwABLgAFFAQJGwAhAFUgAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.Enigmä:BAAALgADCgYJCgAAAA==.Enio:BAAALgAECgMJAwAAAA==.',
Er='Ericuh:BAABLgAECn8eAAMBAAYJsxItVwAjAQABAAYJsxItVwAjAQACAAEJjAeClwAjAAAAAA==.',
Es='Escanör:BAAALgAECgYJEAABLgAECggJGgAGAEAeAA==.Essekk:BAACLgAFFH8TAAIDAAUJrxu6MABkAQADAAUJrxu6MABkAQAuAAQKfy8AAgMACQklH2AWACMDAAMACQklH2AWACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Evodrak:BAAALgADCgYJBwAAAA==.Evokeeznutz:BAAALgAECgcJCQABLgAFFAMJBgAIAOcQAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.Exploreswag:BAAALgAECgcJDwAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.',
['Eí']='Eír:BAAALgAECgUJBQABLgAECggJNwAaAOUdAA==.',
Fa='Fairyholy:BAAALgADCgIJAgAAAA==.Fallenchaos:BAAALgAECgYJBgAAAA==.Famjam:BAABLgAECn8UAAIhAAYJkxGOnwAXAQAhAAYJkxGOnwAXAQAAAA==.Fao:BAAALgAECgQJBQAAAA==.Fastrialimas:BAAALgAECgEJBgAAAA==.Fatpo:BAABLgAECn8gAAMaAAgJzSC6BgDiAgAaAAgJzSC6BgDiAgANAAQJVh8ZOwD9AAABLgAFFAMJCQAcAFAkAA==.Fayjhu:BAABLgAECn8mAAIDAAgJaAt8eQBoAQADAAgJaAt8eQBoAQAAAA==.',
Fe='Ferbos:BAAALgAECgIJAwAAAA==.Feylock:BAABLgAECn8UAAIJAAcJ7RBnhAAcAQAJAAcJ7RBnhAAcAQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgAECgYJBgAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAACLgAFFH8JAAIfAAQJoA9eFwAtAQAfAAQJoA9eFwAtAQAuAAQKfzIAAh8ACQk9HmgIAH0CAB8ACQk9HmgIAH0CAAAA.',
Fr='Frigate:BAABLgAECn8YAAIDAAcJWgUS2QA/AQADAAcJWgUS2QA/AQAAAA==.Frihgate:BAABLgAECn8aAAIRAAgJNhZ2MgDmAQARAAgJNhZ2MgDmAQAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frostmyface:BAAALgAFFAIJAwAAAA==.Frozenbeard:BAAALgAECgcJEwAAAA==.',
Fu='Fugarra:BAAALgAECgQJBQABLgAECgkJFQAWAGYFAA==.Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAACLgAFFH8GAAIgAAMJSR5tGwAjAQAgAAMJSR5tGwAjAQAuAAQKfxYAAiAACAl/IagNAD4CACAACAl/IagNAD4CAAAA.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgAECgcJCAAAAA==.Fuzi:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.',
Fy='Fyafya:BAAALgAFFAEJAQAAAA==.Fyah:BAABLgAECn8ZAAIhAAkJaSCVJwBDAgAhAAkJaSCVJwBDAgABLgAFFAYJFgAiAI0fAA==.Fyaza:BAAALgAECgMJAwAAAA==.',
Ga='Gargamels:BAAALgAECgQJBgABLgAECgkJFQAWAGYFAA==.Gariantel:BAAALgAECgMJCwAAAA==.Garleck:BAAALgAECgUJBQAAAA==.Garou:BAABLgAECn8cAAILAAcJix3fFwALAgALAAcJix3fFwALAgAAAA==.Gaygar:BAAALgADCgcJEwAAAA==.',
Ge='Geekylock:BAAALgAECgUJDgAAAA==.Geekymage:BAAALgAECgMJBAAAAA==.Geekyxgenome:BAAALgADCgEJAQAAAA==.Genesis:BAAALgAFFAMJAwAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgUJDQAAAA==.Gerttie:BAAALgAECgUJCAAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAcJLQAMAPQhAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAAALgAECggJEwAAAA==.Gorehammer:BAABLgAECn8qAAIbAAgJlxmHUAAAAgAbAAgJlxmHUAAAAgAAAA==.Gorto:BAAALgAECgEJAQAAAA==.',
Gr='Grassmoker:BAAALgAECgEJAgAAAA==.Gravediger:BAAALgAECgcJEQAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Grek:BAABLgAFFH8GAAIYAAMJBiHjDQAdAQAYAAMJBiHjDQAdAQAAAA==.Gridxx:BAABLgAECn8WAAMeAAcJDhN3JwBjAQAeAAcJDhN3JwBjAQAZAAEJkAS+RgAiAAAAAA==.Grievex:BAABLgAECn85AAIhAAkJzAnMZQCEAQAhAAkJzAnMZQCEAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.Grimblefritz:BAAALgADCgMJAwAAAA==.Gronthar:BAAALgADCgEJAQAAAA==.',
['Gî']='Gîgâbussy:BAAALgADCgIJAgAAAA==.',
Ha='Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgMJBAAAAA==.Hanyu:BAAALgAECgcJCgAAAA==.Harkelem:BAAALgAECgkJAQAAAA==.Haydayy:BAAALgADCgYJBgAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAABLgAECn8XAAMaAAgJPBUBFQAHAgAaAAgJPBUBFQAHAgAMAAIJ4wPXWgBKAAAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Hemobloom:BAAALgAECgIJAgABLgAFFAQJGwAhAFUgAA==.Hemolock:BAACLgAFFH8GAAIJAAQJmgPZWADmAAAJAAQJmgPZWADmAAAuAAQKfxwAAwkABgmAFpJ0ADoBAAkABgmAFpJ0ADoBAAoAAQkAAMhKAAAAAAEuAAUUBAkbACEAVSAA.Hemostasis:BAACLgAFFH8bAAIhAAQJVSDyFACAAQAhAAQJVSDyFACAAQAuAAQKfycABCEACAlAIpMwAGACACEACAlAIpMwAGACACMABAm8CfNcAJEAABQAAQksDtREACsAAAAA.Herjä:BAABLgAECn83AAMaAAgJ5R1PDAB6AgAaAAgJ5R1PDAB6AgAMAAYJrRNgJQBpAQAAAA==.Hexmora:BAAALgAECgEJAgAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.',
Ho='Homeslice:BAAALgAECgUJBwAAAA==.Hoocha:BAAALgADCgYJBgABLgAFFAMJBgAIAOcQAA==.Hoollymollyy:BAAALgAECgEJAQAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.Hotandcold:BAAALgAECgEJAgAAAA==.',
Hu='Hunterskillz:BAAALgADCgYJBgAAAA==.Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgIJAgAAAA==.Huun:BAABLgAECn8wAAIiAAkJhBz4CQBmAgAiAAkJhBz4CQBmAgAAAA==.',
Hy='Hyasynthia:BAAALgAECgYJBgAAAA==.',
Ia='Iamnsfw:BAAALgAECgcJEgAAAA==.',
Ic='Icelcelance:BAAALgAFFAIJAwAAAA==.',
Il='Illuminee:BAAALgAECgIJAgABLgAECgIJAgAFAAAAAA==.Illydan:BAABLgAECn8iAAMWAAkJFxvwEgCOAgAWAAkJFxvwEgCOAgAVAAEJGAhGXgApAAAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn83AAIDAAkJPSBZDgDxAgADAAkJPSBZDgDxAgAAAA==.Impedup:BAAALgAECgUJBQAAAA==.',
In='Indigø:BAAALgAECgUJDgAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAFFAEJAgAFAAAAAA==.',
Ir='Irezufortips:BAAALgAECgcJAQABLgAECgkJFQAWAGYFAA==.Ironhide:BAAALgAECgIJAgAAAA==.Ironshadow:BAAALgADCgEJAQAAAA==.Irrenadro:BAABLgAECn8WAAIhAAgJJw6+fQB+AQAhAAgJJw6+fQB+AQAAAA==.Irvainee:BAAALgAECgYJDAABLgAECgcJEQAFAAAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Ja='Jadechaos:BAAALgAECgEJAQAAAA==.Jadireux:BAAALgAECgYJDAAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jarnabas:BAAALgAECgcJCAAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jimboslice:BAAALgADCgcJBwAAAA==.Jingleparts:BAAALgAECgUJBQABLgAECggJGwAaANgdAA==.',
Jo='Joes:BAABLgAECn8jAAMRAAcJ9hcHSwCUAQARAAcJ9hcHSwCUAQAEAAYJ3AW3HwCNAAAAAA==.Jonesy:BAAALgAECgUJDAAAAA==.Jophiel:BAAALgADCgQJBAAAAA==.Jorath:BAAALgAECgUJBgABLgAECgkJFQAWAGYFAA==.',
Ju='Juicygossip:BAAALgAECgYJBwAAAA==.Jujupowa:BAABLgAECn8YAAIhAAcJGQW3uwDrAAAhAAcJGQW3uwDrAAAAAA==.Junebug:BAAALgAECgQJBQAAAA==.Justicus:BAAALgADCgMJAwAAAA==.',
['Jë']='Jëssë:BAAALgAECgQJBAAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kagal:BAABLgAECn8WAAIiAAgJ3RExDwDSAQAiAAgJ3RExDwDSAQAAAA==.Kaidan:BAABLgAECn8oAAIRAAkJpBIGOQDPAQARAAkJpBIGOQDPAQAAAA==.Kaipriest:BAAALgAECgQJBAAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kaledra:BAAALgAECgQJBAAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgQJBQAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAFFAMJCAAVAJUjAA==.Katanya:BAAALgAECgYJBgABLgAECgkJIQAIANYfAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8UAAIRAAUJQxPVKQAvAQARAAUJQxPVKQAvAQAAAA==.Keftheals:BAAALgAECgkJCgAAAA==.Keiriline:BAABLgAECn8iAAMkAAcJvRY+DQBXAQAkAAcJvRY+DQBXAQAbAAEJYwCdXQEXAAAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAABLgAECn8fAAIiAAcJPB1lGQC1AQAiAAcJPB1lGQC1AQAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgYJCgAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.Khalysea:BAAALgADCgIJAgABLgAECgkJIQAIANYfAA==.',
Ki='Kiimari:BAAALgAECggJCwAAAA==.Killbreed:BAABLgAECn8mAAIZAAgJWSFVBACVAgAZAAgJWSFVBACVAgAAAA==.Kinkster:BAAALgAECgMJAwAAAA==.Kirinani:BAAALgAECgEJAQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knight:BAAALgAECgYJDAABLgAFFAQJCQAdAPkeAA==.Knuggz:BAABLgAECn8hAAILAAgJ1h4QEgBBAgALAAgJ1h4QEgBBAgAAAA==.',
Ko='Kolduna:BAAALgADCgUJBQAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgADCgkJEQAAAA==.',
Kr='Krestaul:BAAALgAECgcJCQAAAA==.',
Ku='Kurthalan:BAAALgAECgQJDAAAAA==.Kuumaneko:BAABLgAECn8zAAMJAAkJWyGzBgASAwAJAAkJWyGzBgASAwAKAAYJrwcMMQD1AAAAAA==.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJEgAAAA==.Kyledh:BAACLgAFFH8RAAIWAAQJpx/zGgCEAQAWAAQJpx/zGgCEAQAuAAQKfzwAAxYACQkjJh8BAHcDABYACQkjJh8BAHcDACUAAQluIf8jAGIAAAAA.Kyletotems:BAAALgAECgIJAgAAAA==.Kyllgorre:BAAALgAECgEJAQAAAA==.Kynyine:BAAALgADCgcJCAAAAA==.',
La='Lancee:BAAALgAECgUJBQAAAA==.Landridan:BAAALgAECgMJAwAAAA==.Lanstoll:BAAALgAECgUJBAAAAA==.Lanthin:BAAALgADCggJEgAAAA==.Larzoe:BAAALgAECgYJBgABLgAECgkJIgAVAOojAA==.Larzoh:BAABLgAECn8iAAMVAAkJ6iOkAwBGAwAVAAkJ6iOkAwBGAwAWAAMJSw7LxwBnAAAAAA==.Laudrup:BAAALgADCgYJCwAAAA==.Laylaria:BAAALgADCgEJAQAAAA==.',
Le='Lee:BAAALgADCgYJBQABLgAFFAIJBgAbACkfAA==.Legadiaus:BAAALgAECggJCgAAAA==.Lemonheads:BAABLgAECn85AAMMAAkJfRl5CADHAgAMAAkJfRl5CADHAgANAAEJ4QEtagAjAAAAAA==.Lethargy:BAAALgAECgQJBAAAAA==.',
Li='Liaenara:BAAALgADCgYJCwAAAA==.Lidorila:BAAALgAECgMJAwAAAA==.Lightbranger:BAAALgADCgMJAwAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgcJCgABLgAECgYJEwAFAAAAAA==.Lilwiz:BAAALgAECgUJCgAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Linnxs:BAAALgAECgIJAwABLgAECgMJBQAFAAAAAA==.Linnxvx:BAAALgAECgMJBQAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgMJBAAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgAFAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwAFAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgAFAAAAAA==.Loxley:BAAALgAECgUJBQAAAA==.',
Ls='Lshaman:BAABLgAFFH8FAAIBAAMJ7Bs2LgDzAAABAAMJ7Bs2LgDzAAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAAALgAECgcJCQAAAA==.Lunahunter:BAAALgAECgEJAQAAAA==.Lunarcricket:BAAALgAECgUJCAABLgAECgkJMgAUAMwjAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwAFAAAAAA==.',
Ly='Lyncha:BAAALgADCgcJDgABLgAECgkJMgAUAMwjAA==.Lynchà:BAABLgAECn8yAAIUAAkJzCPyAAA6AwAUAAkJzCPyAAA6AwAAAA==.Lynchá:BAAALgADCgIJAgAAAA==.Lynchä:BAAALgADCgEJAQABLgAECgkJMgAUAMwjAA==.',
Ma='Maakun:BAABLgAECn8dAAQaAAcJ3gxoOwBNAQAaAAcJ2gdoOwBNAQANAAUJ8wcWQAD2AAAMAAQJHg2rOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJDgABLgAECgUJBgAFAAAAAA==.Madette:BAAALgADCggJCAABLgAFFAcJLQAMAPQhAA==.Mageapoug:BAAALgADCgcJBwAAAA==.Magia:BAAALgAECgEJAQAAAA==.Magmalance:BAAALgAECgYJCAABLgAECgYJFQAWAOMPAA==.Mahoragga:BAAALgADCgYJBgAAAA==.Mahzad:BAACLgAFFH8JAAIBAAUJciBACgDXAQABAAUJciBACgDXAQAuAAQKfyYAAwEABwljIzoYAFQCAAEABwljIzoYAFQCAAIABgmmDc1HAOQAAAAA.Maladi:BAAALgADCgkJJAAAAA==.Malfrun:BAABLgAECn8pAAMYAAkJLBYxDQDxAQAYAAkJLBYxDQDxAQALAAIJjQU+eQBRAAAAAA==.Marinnite:BAAALgADCgYJDQAAAA==.Markzugrberg:BAAALgADCgkJCQAAAA==.Marox:BAACLgAFFH8IAAIDAAQJwgokUwAhAQADAAQJwgokUwAhAQAuAAQKfxgAAgMACQldHXZDAG4CAAMACQldHXZDAG4CAAAA.Marshmellows:BAAALgAECgYJBgABLgAECgYJHgABALMSAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAACLgAFFH8WAAIJAAUJjiRvFwCgAQAJAAUJjiRvFwCgAQAuAAQKfyMAAwkACQmGJEoVANUCAAkACAmGJEoVANUCAAoAAQkAANtVAG0AAAAA.Matooka:BAABLgAECn8iAAIRAAgJEQ0qVQB1AQARAAgJEQ0qVQB1AQAAAA==.Maynji:BAAALgAECgMJAwAAAA==.Mayushi:BAAALgAECgYJCQAAAA==.',
Mc='Mcthugger:BAAALgAECgEJAQABLgAECgkJLwAhAHEaAA==.',
Me='Meencurry:BAABLgAECn8kAAIDAAgJghWRUwDFAQADAAgJghWRUwDFAQAAAA==.Megozugzug:BAAALgAFFAEJAgAAAA==.Meyneth:BAAALgAECgQJCAAAAA==.',
Mi='Mikaì:BAAALgAECgkJEgAAAA==.Mikehawkener:BAAALgAECgYJDwAAAA==.Mirlone:BAAALgAECgIJAgAAAA==.Misleading:BAAALgAECgUJEQAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Missdead:BAAALgAECgEJAQAAAA==.Mistfisting:BAACLgAFFH8FAAIcAAMJURQJJwC8AAAcAAMJURQJJwC8AAAuAAQKfxQAAhwABwmEHtoaAAECABwABwmEHtoaAAECAAAA.',
Mo='Moderato:BAAALgAECgkJDgAAAA==.Moelleri:BAABLgAECn8dAAIbAAgJaBmVSADGAQAbAAgJaBmVSADGAQAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgUJBgAFAAAAAA==.Moneymage:BAAALgAECgcJCwAAAA==.Monkgroom:BAACLgAFFH8SAAIcAAQJpQrSIQDlAAAcAAQJpQrSIQDlAAAuAAQKfx0AAxwACQmaFA8XAAkCABwACQmaFA8XAAkCAB0ABgnyCto5ADYBAAAA.Monsignor:BAAALgAECgIJCAAAAA==.Montra:BAACLgAFFH8HAAITAAMJ6g4VEAC9AAATAAMJ6g4VEAC9AAAuAAQKfzMAAxMACQn6HJsEAJ0CABMACQn6HJsEAJ0CABkABQkCCf4eAOsAAAAA.Mordach:BAAALgAECgEJAQAAAA==.Moreilira:BAAALgAECgYJEQAAAA==.Mornshield:BAABLgAECn8fAAMhAAYJWxSmkQBZAQAhAAYJIxCmkQBZAQAUAAUJUxMIJgDZAAABLgAECgkJFQAWAGYFAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motorinkashi:BAABLgAECn8aAAMOAAkJ5h6mBgAzAwAOAAkJ5h6mBgAzAwATAAMJFw/7OAB3AAAAAA==.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAABLgAECn8aAAIYAAgJoRR+FgBpAQAYAAgJoRR+FgBpAQAAAA==.Muddthir:BAAALgAECgQJBAABLgAECggJGgAYAKEUAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCwAAAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwAhANocAA==.',
Na='Nahaine:BAAALgADCggJCAAAAA==.Nazrra:BAABLgAECn8bAAIYAAkJIxRkEAACAgAYAAkJIxRkEAACAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgAECgEJAQAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Nenad:BAAALgADCgEJAQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nerodic:BAAALgADCgYJBgABLgAFFAQJEwAbAMgYAA==.Nestaah:BAAALgAFFAIJBAAAAA==.Nettra:BAAALgAECgIJCgAAAA==.Newtnewt:BAAALgAECgUJBgAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nicneven:BAAALgADCgkJCQAAAA==.Nininbrew:BAAALgAECgEJAgABLgAECgYJEgAFAAAAAA==.Nirath:BAABLgAECn82AAIDAAkJ6RJ1OgAUAgADAAkJ6RJ1OgAUAgAAAA==.',
No='Nobainer:BAAALgADCgYJCwAAAA==.Noed:BAAALgAECgMJBgAAAA==.Nohkana:BAAALgAECgEJAQAAAA==.Nohkano:BAABLgAECn8uAAIgAAkJhCUIAQBbAwAgAAkJhCUIAQBbAwAAAA==.Nokinkshame:BAAALgADCggJCQABLgAECggJGwAaANgdAA==.Nokt:BAAALgADCgQJBAAAAA==.Noobymonk:BAAALgAECggJEgAAAA==.Noralise:BAAALgAECgYJEwAAAA==.Northerndk:BAABLgAECn8WAAIbAAcJKgVQwQDQAAAbAAcJKgVQwQDQAAAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgQJCAAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.Nutthunter:BAAALgAECgEJAwAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAIDAAgJVhTDbAD8AQADAAgJVhTDbAD8AQAAAA==.',
Oa='Oakmain:BAAALgAECgUJBQAAAA==.',
Oc='Octavarium:BAABLgAECn8hAAIcAAgJExzvEABlAgAcAAgJExzvEABlAgAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.Odinspriest:BAAALgADCgcJBwAAAA==.Odinsvulpera:BAAALgADCgYJBwAAAA==.',
Oe='Oennomaus:BAAALgAECgUJBgAAAA==.',
Of='Offspec:BAAALgAECgEJAgAAAA==.',
Oh='Ohyshii:BAAALgAECgMJBQAAAA==.',
Ol='Olorinziln:BAAALgAECgYJBgAAAA==.',
On='Oneshothel:BAAALgAECgYJEQAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwAhANocAA==.',
Or='Orcpeon:BAAALgAECgYJDQABLgAECggJNQAhAKAdAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAAALgAECgYJEgABLgAECggJGwAaANgdAA==.Overdoze:BAAALgADCgYJBgAAAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Paichan:BAAALgAECgEJAQAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgADCgUJBQAAAA==.Pancaked:BAAALgAECggJEAABLgAECggJGwAaANgdAA==.Pantheons:BAAALgADCgIJAwAAAA==.Paradon:BAAALgADCgEJAQAAAA==.Paradox:BAAALgAECgQJBAABLgAFFAQJEAAZACsbAA==.Parsi:BAACLgAFFH8FAAIlAAIJSxj7BwCPAAAlAAIJSxj7BwCPAAAuAAQKfxQAAiUABwkiGLENAEkBACUABwkiGLENAEkBAAAA.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Penut:BAAALgAECgEJAQAAAA==.Perritax:BAABLgAECn8iAAIDAAcJdhE3dwBtAQADAAcJdhE3dwBtAQAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwAAAA==.Phoebelyria:BAAALgAECgYJEQAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgAFAAAAAA==.',
Pi='Pickelz:BAAALgADCgMJAwAAAA==.Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgQJBgAAAA==.Pingdoo:BAAALgAECgIJAwAAAA==.',
Po='Pofat:BAABLgAFFH8JAAIcAAMJUCROGAA7AQAcAAMJUCROGAA7AQAAAA==.Polis:BAABLgAECn81AAIhAAgJoB2aJgBIAgAhAAgJoB2aJgBIAgAAAA==.Pomol:BAAALgAECgcJEAAAAA==.Pomoly:BAAALgAECgEJAQAAAA==.Poppafury:BAABLgAECn8ZAAIYAAcJJBXzFQBvAQAYAAcJJBXzFQBvAQAAAA==.Potent:BAABLgAECn8gAAMbAAgJ4RHEbABmAQAbAAgJ4RHEbABmAQAmAAQJbQaPOgBvAAAAAA==.Poubear:BAAALgAECgIJAgABLgAECgkJFQAWAGYFAA==.Pougadina:BAAALgAECgYJCAABLgAFFAMJCQAcAFAkAA==.',
Pr='Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAACLgAFFH8IAAIbAAMJ1gi0ggDPAAAbAAMJ1gi0ggDPAAAuAAQKfxgAAxsACAn1FmFMALoBABsACAn1FmFMALoBACYAAQlLBH5PABcAAAAA.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAAALgAECgcJEgABLgAECgkJFQAWAGYFAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Qi='Qizzle:BAAALgADCgMJAwAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAIhAAYJYxbTigBlAQAhAAYJYxbTigBlAQAAAA==.Ramshunter:BAABLgAECn8fAAMRAAkJFiFcBwAaAwARAAkJFiFcBwAaAwAEAAIJ4xFuLwBAAAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgAECgQJCAAAAA==.Ratnob:BAABLgAECn8uAAIbAAkJbRoJIQBhAgAbAAkJbRoJIQBhAgAAAA==.Ravnaar:BAAALgAECgkJDwAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.',
Re='Reddemon:BAAALgAECgEJAQABLgAFFAMJBgAYAAYhAA==.Redstraw:BAAALgADCgYJBwAAAA==.Relda:BAAALgAFFAIJAgAAAA==.Remye:BAAALgAECgkJCQAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Rennshi:BAACLgAFFH8IAAIVAAMJlSNxCwAnAQAVAAMJlSNxCwAnAQAuAAQKfyEAAhUACQlBJAgEADsDABUACQlBJAgEADsDAAAA.Retpally:BAABLgAFFH8PAAIYAAYJGhRDBQCtAQAYAAYJGhRDBQCtAQAAAA==.Reyikrat:BAAALgAECgQJCAAAAA==.Rezmee:BAACLgAFFH8IAAIbAAMJJSXNVAAkAQAbAAMJJSXNVAAkAQAuAAQKfxgAAhsACQmII3EOANkCABsACQmII3EOANkCAAAA.',
Rh='Rheaf:BAAALgAECgYJCQAAAA==.',
Ri='Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8WAAIDAAcJPxGIvgBmAQADAAcJPxGIvgBmAQAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rolexiós:BAAALgADCgcJBwAAAA==.Rosario:BAACLgAFFH8RAAMiAAQJah5BBgB/AQAiAAQJah5BBgB/AQAEAAIJOQ1KHwCZAAAuAAQKfy0AAwQACQmyIakNANgCAAQACAmhIakNANgCACIACAklGT0RAAkCAAAA.Royfan:BAAALgAECgQJBAAAAA==.',
Ry='Ryotwar:BAAALgAECgEJAQAAAA==.Rythmatic:BAACLgAFFH8IAAIfAAMJ6yQ6FQA7AQAfAAMJ6yQ6FQA7AQAuAAQKfyoAAx8ACQm/JVIBAE8DAB8ACQm/JVIBAE8DACcABgkNHmQHAL8BAAAA.Ryvenox:BAAALgADCgcJBwAAAA==.',
['Ré']='Rénae:BAAALgAECgkJAgABLgAECgkJCAAFAAAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Saccharine:BAABLgAECn8hAAMMAAkJCBeiDQBoAgAMAAkJCBeiDQBoAgANAAEJdAAWbQAHAAAAAA==.Sakieri:BAABLgAECn85AAINAAkJix5VCQCYAgANAAkJix5VCQCYAgAAAA==.Salinomycin:BAAALgAECgYJDgAAAA==.Saltyaf:BAAALgADCgMJAwAAAA==.Saltymcnalty:BAAALgAECgEJAQAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sandolorian:BAAALgAECgYJBgAAAA==.Sandordel:BAAALgADCgYJDQAAAA==.Sangan:BAABLgAECn8ZAAIDAAYJQR38aQCLAQADAAYJQR38aQCLAQAAAA==.Sanguini:BAABLgAECn8nAAIDAAgJxhj3SADlAQADAAgJxhj3SADlAQAAAA==.Sathari:BAAALgAECgQJCAAAAA==.',
Sc='Schmelzen:BAABLgAFFH8JAAIDAAUJUBXTPwBEAQADAAUJUBXTPwBEAQAAAA==.Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAFFAEJAQABLgAFFAEJAgAFAAAAAA==.Selaris:BAAALgAECgYJEQAAAA==.Selathviala:BAAALgADCgMJBQAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8YAAMPAAcJ4h35CwDMAQAPAAYJYhv5CwDMAQAQAAQJmhvJAQCDAQAuAAQKfywAAxAACQnJIsEBAC8DABAACAlJI8EBAC8DAA8ACAlUIywIAL0CAAAA.',
Sh='Shadowblitzx:BAAALgAECgUJEAAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAFFAQJCQAfAKAPAA==.Shangan:BAAALgAECgEJAgAAAA==.Shapestalker:BAAALgADCgEJAQAAAA==.Sharana:BAAALgAECgQJBAAAAA==.Shazzie:BAAALgADCgUJBQAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgAECgIJAwAAAA==.Shirrazaha:BAAALgADCgMJAwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgABLgAFFAMJCQADAAEeAA==.',
Si='Silaris:BAAALgADCgMJBgAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Sinnur:BAAALgAECgQJCQAAAA==.Sinsear:BAAALgADCgYJBgAAAA==.',
Sk='Skeezer:BAABLgAFFH8GAAIIAAMJ5xADBQD2AAAIAAMJ5xADBQD2AAAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizzie:BAAALgAECgYJDAAAAA==.Slizziore:BAAALgAECgEJAQAAAA==.Slizzle:BAAALgAECgEJAQAAAA==.Slizzley:BAAALgAECgEJAgAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.',
Sm='Smackdiver:BAAALgADCgYJAwAAAA==.Smarfus:BAAALgAECgYJCQABLgAFFAMJBgAYAAYhAA==.Smilingdemon:BAAALgAECgQJBQAAAA==.Smilingp:BAAALgADCgkJDwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAAALgAECgYJEQAAAA==.Snarge:BAACLgAFFH8SAAIHAAYJ2hRMAgCJAQAHAAYJ2hRMAgCJAQAuAAQKfxkABAcACQkpGSAKADACAAcACQkpGSAKADACAAEABQlqCE54ALkAAAIAAQkjEsaDADsAAAAA.Sneaktee:BAAALgAECgMJBAABLgAECggJGAAbAK8cAA==.',
So='Soone:BAAALgAECgkJAQAAAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Sparkydrac:BAAALgAECgYJBgABLgAECgYJFQAWAOMPAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spness:BAAALgAECgUJBQAAAA==.Spunky:BAAALgAECgQJBwAAAA==.',
Sq='Squeaksune:BAAALgADCgcJCAAAAA==.Squiish:BAABLgAECn8VAAIDAAcJDA2YhgBOAQADAAcJDA2YhgBOAQAAAA==.',
Sr='Srorcalot:BAABLgAECn8UAAIbAAcJ7AzeggA4AQAbAAcJ7AzeggA4AQABLgAECgkJFQAWAGYFAA==.',
St='Steppedon:BAAALgAECgYJEwAAAA==.Stingerai:BAABLgAECn8cAAIRAAkJJyC2GwBWAgARAAkJJyC2GwBWAgAAAA==.Stingeret:BAAALgADCgMJAwABLgAECgkJHAARACcgAA==.Stingerge:BAAALgAECgMJBAABLgAECgkJHAARACcgAA==.Stormweaverr:BAAALgAFFAEJAQABLgAFFAMJBgAYAAYhAA==.',
Su='Sunbeamer:BAAALgAECgUJCAAAAA==.Sureman:BAAALgAECgMJBQAAAA==.Suun:BAAALgADCgMJAwAAAA==.',
Sw='Swaggie:BAAALgADCgMJAwAAAA==.Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylentsniper:BAAALgAECgEJAQABLgAECgkJFQAWAGYFAA==.Sylvesters:BAAALgADCgcJBwABLgAECgUJBgAFAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
Ta='Tacosalad:BAAALgAECgcJCwABLgAECggJGwAaANgdAA==.Taellas:BAAALgADCgMJAwAAAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Tamb:BAABLgAECn8fAAIOAAYJwRT2SQBEAQAOAAYJwRT2SQBEAQAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tankndspank:BAAALgADCgYJBgAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Tark:BAAALgADCgYJBwAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwAFAAAAAA==.Tauntisoff:BAAALgADCgMJAwAAAA==.',
Te='Tedious:BAAALgAECgYJDQAAAA==.Teehuntee:BAAALgAECgYJBwABLgAECggJGAAbAK8cAA==.Teepal:BAAALgAECgcJCwABLgAECggJGAAbAK8cAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAABLgAECn8gAAIHAAYJkR6uDQCeAQAHAAYJkR6uDQCeAQAAAA==.Teribullduce:BAACLgAFFH8OAAIiAAQJ+RjXCgBVAQAiAAQJ+RjXCgBVAQAuAAQKf08AAiIACQk2HikEANQCACIACQk2HikEANQCAAAA.Terscheckii:BAAALgAFFAIJBAAAAA==.',
Th='Theslimer:BAABLgAECn8ZAAMRAAkJRhi3KgAJAgARAAgJEBq3KgAJAgAEAAYJpQqSVQDzAAAAAA==.Thesukuna:BAAALgAECgUJBwAAAA==.Thingol:BAAALgADCgcJCgAAAA==.Thormor:BAACLgAFFH8tAAIMAAcJ9CEvAwCyAgAMAAcJ9CEvAwCyAgAuAAQKfy4ABAwACQk8JPsAAJoDAAwACQk8JPsAAJoDABoABwnoHiMWACwCAA0ABQmVHp80AEUBAAAA.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAABLgAECn8vAAMhAAkJcRpFJwBEAgAhAAkJcRpFJwBEAgAUAAIJbAZnQAA5AAAAAA==.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAABLgAECn8lAAMUAAgJfgxHGgAZAQAUAAgJfgxHGgAZAQAhAAMJHgoB/gCYAAAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tigg:BAAALgADCgUJCAAAAA==.Tiimmyy:BAAALgAECgYJDAAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDwAAAA==.Tinkertotem:BAAALgADCgkJCQAAAA==.Tinyandcute:BAAALgADCgkJDwABLgAECggJGwAaANgdAA==.Tiravana:BAAALgAECgIJAgAAAA==.',
To='Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgADCgYJBwABLgAECggJGgAIACkTAA==.',
Tr='Trebuchet:BAAALgAECggJEAAAAA==.Treefrog:BAAALgADCgkJDAAAAA==.Treeshine:BAAALgAECgcJAQABLgAECggJFAAWAMMVAA==.Trtmiles:BAAALgAECgcJDwAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAABLgAECn8gAAIDAAgJNCI6GgCiAgADAAgJNCI6GgCiAgAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgMJBgAAAA==.',
Ub='Ubeenbained:BAABLgAECn8kAAIVAAgJfgyoHgBIAQAVAAgJfgyoHgBIAQAAAA==.',
Un='Unlock:BAABLgAECn8XAAIRAAkJFhiAHwBAAgARAAkJFhiAHwBAAgAAAA==.',
Ur='Urgmathron:BAABLgAECn8dAAIUAAcJ7SIOBwBDAgAUAAcJ7SIOBwBDAgAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Valadashora:BAAALgAECgEJAQAAAA==.Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8XAAMBAAYJNwNvGQBVAQABAAYJNwNvGQBVAQACAAQJnRKgDAAhAQAuAAQKfyUAAwIACQm8IJ4HAMMCAAIACQm8IJ4HAMMCAAEAAQlsGUanAEIAAAAA.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgAECgQJDAAAAA==.',
Vd='Vdr:BAAALgADCgEJAgAAAA==.',
Ve='Velantheron:BAAALgAECgYJCgAAAA==.Velosityy:BAAALgAECgMJAwAAAA==.Vezrx:BAAALgAFFAIJAwAAAA==.',
Vi='Vinsmoke:BAAALgAECgYJDgAAAA==.Vitanimm:BAAALgADCgIJAwAAAA==.Vitiate:BAAALgAECgYJBgAAAA==.',
Vo='Voinox:BAAALgADCgcJDQABLgADCgcJEwAFAAAAAA==.Volcanoez:BAAALgAECgQJCwAAAA==.',
Vr='Vrezor:BAAALgAECgQJDAAAAA==.',
Vy='Vyolnc:BAAALgAECgQJCAAAAA==.Vyrexiona:BAABLgAECn8YAAMPAAcJ2BmDGAAMAgAPAAcJ2BmDGAAMAgAQAAEJtwIURgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgcJDAAAAA==.',
Wa='Warthelian:BAAALgADCgcJBwABLgAECgYJEQAFAAAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAIhAAgJ2hwnJQCSAgAhAAgJ2hwnJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECggJEAAAAA==.',
Wo='Wokthisway:BAAALgAECgQJCAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wreck:BAAALgADCgYJBgABLgAECgEJEgAFAAAAAA==.',
Wy='Wych:BAAALgAECgYJDwABLgAECggJHwAKAO4eAA==.Wynain:BAAALgADCgUJBQAAAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAAALgAECgYJEwAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yappor:BAAALgAECgYJBgAAAA==.',
Ye='Yekteniya:BAAALgAECgYJCQAAAA==.Yerrback:BAAALgAECgMJAwABLgAECgQJBgAFAAAAAA==.',
Yi='Yibbers:BAAALgADCgIJAgAAAA==.Yiimmyy:BAAALgADCgEJAQAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yur:BAAALgADCgcJDAABLgAECggJGgAGAEAeAA==.Yutch:BAAALgAECgYJCgAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAAALgAECgcJDAAAAA==.Zakkydrakky:BAABLgAECn8hAAMoAAkJIQ3iFABZAQAoAAgJLg3iFABZAQAPAAYJPgj9SgDWAAAAAA==.Zani:BAAALgAECgIJAgAAAA==.Zarashara:BAABLgAECn8lAAMgAAgJFBROJgBdAQAgAAcJERZOJgBdAQAdAAgJcQjXLwAfAQAAAA==.',
Ze='Zedward:BAEALgAECgEJAgAAAA==.Zelta:BAAALgADCgkJEwAAAA==.Zerise:BAAALgAECgUJCwAAAA==.',
Zo='Zolidus:BAAALgAECgQJBAAAAA==.Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAFFAEJAgAFAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8jAAIhAAkJKBLIUgCyAQAhAAkJKBLIUgCyAQAAAA==.Zun:BAAALgAECggJDQAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Èz']='Èzili:BAAALgAECgYJCwAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMbAAgJRRRZVgDuAQAbAAgJ/BJZVgDuAQAkAAUJxAxTGQC8AAAAAA==.',
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
