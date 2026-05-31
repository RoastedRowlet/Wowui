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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Mage-Frost','Hunter-Marksmanship','Unknown-Unknown','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Priest-Discipline','DemonHunter-Devourer','Priest-Shadow','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Mage-Arcane','Druid-Guardian','Paladin-Protection','DemonHunter-Havoc','Warrior-Arms','Warrior-Protection','Druid-Feral','Priest-Holy','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Druid-Balance','Rogue-Subtlety','Paladin-Retribution','Hunter-Survival','Paladin-Holy','DeathKnight-Frost','DemonHunter-Vengeance','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAABLgAECn8aAAMBAAgJEQxFUgBLAQABAAgJEQxFUgBLAQACAAEJKAUNoQAmAAAAAA==.Aaramis:BAACLgAFFH8NAAIBAAMJaQzZRgC0AAABAAMJaQzZRgC0AAAuAAQKfzYAAgEACQkxFiIpAP4BAAEACQkxFiIpAP4BAAAA.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ac='Achin:BAAALgADCgUJBQAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAABLgAECn8UAAIDAAgJEwQruQD2AAADAAgJEwQruQD2AAAAAA==.',
Ag='Aggrodk:BAAALgAECgIJAgAAAA==.',
Ah='Ahchu:BAAALgAECgIJAgAAAA==.Ahiru:BAAALgAECgMJAwAAAA==.',
Ai='Aidoffhealer:BAAALgAECgUJCwAAAA==.',
Al='Alariah:BAAALgAFFAEJAQAAAQ==.Alaín:BAABLgAECn8jAAIEAAgJuBheCgCxAQAEAAgJuBheCgCxAQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgAFAAAAAA==.Aldoraline:BAAALgADCgQJBgAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQABLgAECgEJAgAFAAAAAA==.Alystair:BAAALgADCgQJCAABLgAECgkJIQAGAGQiAA==.',
Am='Ambellina:BAAALgAECgQJCQAAAA==.Ampse:BAAALgAECgUJCAAAAA==.Amzy:BAAALgADCgYJCQABLgAECgEJAQAFAAAAAA==.',
An='Anaria:BAAALgAECggJEAAAAA==.Angbu:BAABLgAECn8iAAMHAAcJQRczEgByAQAHAAcJQRczEgByAQACAAEJoARgkQAmAAAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Aphadiri:BAAALgAECgMJBAAAAA==.Apinkninja:BAABLgAECn8nAAIDAAcJGxolaACTAQADAAcJGxolaACTAQAAAA==.',
Ar='Aranyssa:BAABLgAECn8hAAQIAAkJ1h/VCAC4AQAIAAYJhSDVCAC4AQAJAAYJ3hHxogDvAAAKAAQJLhrBHQCmAAAAAA==.Arch:BAAALgAECgIJAgABLgAFFAUJHAAJAMYkAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAABLgAFFH8JAAILAAMJAQvSMADKAAALAAMJAQvSMADKAAAAAA==.Ardur:BAAALgAECgMJAwAAAA==.Ark:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Arkork:BAAALgAECgEJAgAAAA==.Arnøld:BAABLgAFFH8FAAIMAAMJowOFLgCoAAAMAAMJowOFLgCoAAAAAA==.Arruna:BAABLgAECn8XAAINAAcJTRGBggD+AAANAAcJTRGBggD+AAAAAA==.Artorìas:BAAALgADCgkJCwABLgAECgkJIQAGAGQiAA==.',
As='Asham:BAABLgAECn85AAMMAAgJ5xEfGwDVAQAMAAgJ5xEfGwDVAQAOAAIJswqTZABcAAAAAA==.Ashenbloom:BAABLgAECn8hAAIPAAgJiglTVwAhAQAPAAgJiglTVwAhAQAAAA==.Asiago:BAABLgAECn8XAAMQAAkJ4BIgLQBYAQAQAAkJ4BIgLQBYAQARAAEJRge0PwAxAAAAAA==.Aspect:BAABLgAECn8hAAMGAAkJZCJXAAAqAwAGAAkJZCJXAAAqAwADAAEJWRLEYAE/AAAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgAECgQJBgAAAA==.',
Av='Avacúma:BAAALgAECgIJAwAAAA==.Avvalethra:BAABLgAECn9BAAMSAAkJGR6IEQCvAgASAAkJGR6IEQCvAgAEAAgJqg3XOwBwAQAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgcJDAAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAcJGAARAOIdAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Babyball:BAAALgAECggJDAAAAA==.Bachshots:BAABLgAFFH8NAAISAAUJKw+tMwAuAQASAAUJKw+tMwAuAQAAAA==.Backstabbath:BAAALgADCgUJBQABLgAECgkJFQANAGYFAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgYJDgABLgAFFAIJAgAFAAAAAA==.Bainey:BAAALgADCgIJAgABLgADCgYJCwAFAAAAAA==.Bananataffy:BAABLgAECn8XAAIPAAcJ2RT4NQCuAQAPAAcJ2RT4NQCuAQAAAA==.Barackoshama:BAABLgAECn8eAAICAAkJAxxUGwDtAQACAAkJAxxUGwDtAQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Basedween:BAAALgADCgcJGAAAAA==.Battlescars:BAAALgAFFAIJAgAAAA==.Baw:BAABLgAECn88AAMDAAkJ6R62FQDCAgADAAkJ6R62FQDCAgATAAMJFwmTFQBvAAAAAA==.',
Be='Bearelf:BAAALgAECgMJAwAAAA==.Bearlinwall:BAABLgAECn8YAAIUAAYJFxDeLQDPAAAUAAYJFxDeLQDPAAAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.Bews:BAAALgAFFAIJAwAAAA==.',
Bi='Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigdumbo:BAAALgAECgQJBQABLgAFFAMJBQABAOwbAA==.Bigskydh:BAAALgAECgYJEAAAAA==.Bigskymage:BAAALgAECgUJDgAAAA==.Bigskymoney:BAAALgAECgQJBAAAAA==.Billybones:BAAALgAECgYJDAAAAA==.Bip:BAAALgADCgEJAQAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAECgkJFAABAI4WAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECggJJQAVAH4MAA==.Bladedozzer:BAAALgAECgcJCgAAAA==.Blindinglite:BAACLgAFFH8IAAIWAAMJexgNEgDpAAAWAAMJexgNEgDpAAAuAAQKfyUAAhYACAl7Ij8MAEQCABYACAl7Ij8MAEQCAAAA.Blindtoast:BAAALgAECgIJAgAAAA==.Blkpriest:BAAALgAECgIJAwAAAA==.Bloodhaze:BAACLgAFFH8LAAIWAAMJpCGtDwAFAQAWAAMJpCGtDwAFAQAuAAQKfyAAAhYACQmjHxgLAK8CABYACQmjHxgLAK8CAAAA.Blorp:BAACLgAFFH8UAAINAAQJkRcHNgAmAQANAAQJkRcHNgAmAQAuAAQKfx0AAg0ACAnfHMwlAHACAA0ACAnfHMwlAHACAAAA.',
Bo='Bodizzle:BAAALgAECgEJAwAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgQJCQAAAA==.Borestus:BAAALgAECgYJDAAAAA==.Bouldur:BAABLgAECn8ZAAQLAAYJvAoRUADwAAALAAYJJwkRUADwAAAXAAQJLAg8RACbAAAYAAEJzgI2WAAWAAAAAA==.Bownystark:BAABLgAECn8eAAIEAAcJCCJHFQCIAgAEAAcJCCJHFQCIAgAAAA==.Bozz:BAAALgAECgQJBQAAAA==.',
Br='Brickingit:BAAALgAECgYJCwAAAA==.Brieter:BAAALgAECgcJDAABLgAECgkJFwAQAOASAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokendrako:BAAALgAFFAQJBAAAAA==.Brokikobo:BAAALgADCggJCwAAAA==.Broly:BAAALgAECgEJAQAAAA==.Bromthelian:BAAALgADCgkJCQABLgAECgYJFwASAOcaAA==.Broughston:BAAALgAECgEJAQAAAA==.Brutusx:BAABLgAECn8fAAISAAYJnQ3rgAAkAQASAAYJnQ3rgAAkAQAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAABLgAECn8jAAMUAAgJMR9sBwBiAgAUAAgJMR9sBwBiAgAZAAMJwQTQOABUAAAAAA==.Burntcring:BAAALgAECgUJCwAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJDgAAAA==.',
Bx='Bxxberry:BAAALgAECgUJDgAAAA==.',
Ca='Calari:BAAALgADCgEJAQAAAA==.Camipriest:BAAALgAECgEJAQAAAA==.Carllina:BAAALgAECgYJBgAAAA==.Carmane:BAAALgAECgUJBQAAAA==.Casstyelle:BAAALgAECgQJBgABLgAECggJGwAIACkTAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgUJCgABLgAECgkJIQAIANYfAA==.Cet:BAAALgAECgQJBAABLgAECgkJIQAGAGQiAA==.Cexiback:BAAALgAECgUJDAAAAA==.',
Ch='Chairon:BAAALgAECgQJBAABLgAECgUJEAAFAAAAAA==.Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheesus:BAAALgAECgcJDAABLgAECgkJFwAQAOASAA==.Chicharon:BAAALgAECgUJDwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECgkJHwAaAIocAA==.Chipsnsalsa:BAAALgAECgQJBAABLgAECgkJHwAaAIocAA==.Chocoriffic:BAABLgAECn8fAAIaAAkJihxsCQC8AgAaAAkJihxsCQC8AgAAAA==.Chokoballs:BAAALgAECgEJAQABLgAECgkJNgAbAHwYAA==.Chokoballz:BAABLgAECn8VAAMcAAgJ4RpzGQDOAQAcAAgJjhVzGQDOAQAdAAUJ3BroLgA3AQABLgAECgkJNgAbAHwYAA==.Churva:BAAALgAECgEJAQABLgAECgkJGgANAHwJAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAABLgAECn8tAAMUAAkJ9B6dAwDUAgAUAAkJ9B6dAwDUAgAZAAEJxBEYRAA0AAAAAA==.Coldbrewz:BAAALgAECgYJDwAAAA==.Conalbegle:BAAALgAECgIJAgAAAA==.Condensation:BAAALgADCgEJAQAAAA==.Coopah:BAAALgAECgkJBQAAAA==.Corgibutts:BAAALgAFFAIJAgAAAA==.Corvyr:BAAALgADCgkJCQAAAA==.',
Cr='Crackjones:BAAALgAECgcJCAAAAA==.Crapsrocks:BAAALgAECgYJCgAAAA==.Crazydave:BAABLgAECn8aAAIaAAkJ7xEoIwDMAQAaAAkJ7xEoIwDMAQAAAA==.Creemywitchu:BAAALgADCgEJAQABLgADCgcJBwAFAAAAAA==.Crisgmt:BAAALgAECgcJDQAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAABLgAECn8XAAIeAAgJ2RupFgBAAgAeAAgJ2RupFgBAAgAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Cryptìc:BAACLgAFFH8RAAIOAAcJkRnkAwAXAgAOAAcJkRnkAwAXAgAuAAQKfx4AAg4ACAmPI/IIAKcCAA4ACAmPI/IIAKcCAAEuAAUUBgkXAAMABRkA.Cryptîc:BAACLgAFFH8XAAIDAAYJBRmhIwCtAQADAAYJBRmhIwCtAQAuAAQKfzAAAgMACAnSJQkWAMACAAMACAnSJQkWAMACAAAA.Cráckjones:BAAALgADCgEJAQAAAA==.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8YAAIDAAcJjxlOXwAdAgADAAcJjxlOXwAdAgAAAA==.Dabbia:BAACLgAFFH8HAAMIAAQJRxFsDACUAAAJAAMJMgz9bwDLAAAIAAIJQBNsDACUAAAuAAQKfyQABAoACAn7HAkTALMBAAkABgl4G5JXAMEBAAoABgnlGgkTALMBAAgABgnyHO8JAKIBAAAA.Daedleus:BAAALgADCgQJBAAAAA==.Damented:BAABLgAECn8bAAMIAAgJKRONDABwAQAIAAgJKRONDABwAQAJAAMJyw+dzwCjAAAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnchild:BAAALgADCgEJAQABLgAECgYJHgABALMSAA==.Dawnpaw:BAABLgAECn8iAAMeAAkJqhNaIgCgAQAeAAgJcxFaIgCgAQAcAAUJpBVfPQDxAAAAAA==.Daymonesus:BAAALgAECgUJBQAAAA==.',
De='Deathballz:BAABLgAECn82AAIbAAkJfBggMgAiAgAbAAkJfBggMgAiAgAAAA==.Deathsbreach:BAABLgAECn8VAAINAAYJ4w86hQD4AAANAAYJ4w86hQD4AAAAAA==.Deathsmite:BAAALgAECgIJBAAAAA==.Deathtee:BAABLgAECn8YAAIbAAgJrxxPRgAiAgAbAAgJrxxPRgAiAgAAAA==.Deepwaters:BAAALgADCgcJDgAAAA==.Dekuslice:BAABLgAECn8cAAIfAAcJrhQcKwBgAQAfAAcJrhQcKwBgAQAAAA==.Delafant:BAAALgAECgYJCwAAAA==.Deldaris:BAAALgAECgMJAwAAAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonarc:BAAALgAECgYJBgAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Derpyderp:BAAALgAECgEJAQABLgAECgkJFAADALoMAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgAFAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAAALgAECgQJBAAAAA==.',
Di='Diatomaceous:BAAALgAECgEJAQAAAA==.Dinkys:BAAALgADCgYJCwABLgAECgYJDwAFAAAAAA==.Dinsum:BAAALgADCgcJFwAAAA==.Diogenist:BAAALgAECgUJCgAAAA==.Dirtydhunter:BAAALgAECgYJBgAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAAALgAFFAMJAwABLgAFFAMJCAAgAOskAA==.',
Do='Dogdad:BAAALgADCgcJCwAAAA==.Doktarboom:BAAALgADCgIJAQAAAA==.Doktardoodad:BAAALgAECgYJCwAAAA==.Doktartides:BAAALgAECgEJAQAAAA==.Doktarzen:BAAALgAECgQJBgAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Donut:BAAALgAECgUJCAAAAA==.Doomslayer:BAABLgAECn8aAAINAAkJfAn0YgB4AQANAAkJfAn0YgB4AQAAAA==.Doresearch:BAABLgAECn8iAAICAAgJkBV+KQCKAQACAAgJkBV+KQCKAQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAABLgAECn8ZAAIJAAgJSh93OQDnAQAJAAgJSh93OQDnAQAAAA==.Dragontee:BAAALgADCgQJBAABLgAECggJGAAbAK8cAA==.Drakarys:BAAALgAECgYJCwAAAA==.Drakex:BAAALgAECgUJBwAAAA==.Drakoswrath:BAAALgAECgUJBgAAAA==.Dreamyskull:BAAALgADCgQJAgAAAA==.Drengist:BAABLgAECn8zAAIdAAkJhRovDQBQAgAdAAkJhRovDQBQAgAAAA==.Drexybear:BAABLgAECn8pAAMEAAkJFiGwAQDnAgAEAAkJoh+wAQDnAgASAAgJdCF2HQBfAgAAAA==.Drezbi:BAAALgAECgUJEwAAAA==.Droodmon:BAAALgAECgMJBQAAAA==.Drpally:BAAALgADCgEJAQAAAA==.Drpebbles:BAAALgAECgQJCwAAAA==.Druidskillz:BAAALgADCgEJAQAAAA==.Druisty:BAAALgAECgEJAQAAAA==.',
Du='Dulcineru:BAAALgADCgYJCgAAAA==.Dunbarth:BAABLgAECn8jAAIhAAkJbg0sdwBlAQAhAAkJbg0sdwBlAQAAAA==.Durzaman:BAAALgAECgYJDQAAAA==.Durzuk:BAAALgAECgMJAwAAAA==.Duskhoof:BAAALgADCgIJAwAAAA==.',
Dy='Dynastyy:BAAALgAECgkJBwAAAA==.',
['Dé']='Dévílyñ:BAABLgAECn8gAAIJAAYJ2AzCkgAMAQAJAAYJ2AzCkgAMAQAAAA==.',
['Dü']='Dük:BAABLgAECn8YAAMJAAcJjxFNjgAUAQAJAAYJMRJNjgAUAQAKAAIJZA5RTACIAAAAAA==.',
Ed='Eddai:BAAALgAECgEJAQAAAA==.',
Ef='Eff:BAAALgAECgkJDAAAAA==.',
Eg='Eggy:BAAALgAECgkJDgAAAA==.',
Ek='Eks:BAAALgADCgkJHAAAAA==.',
El='Eldraaqeyn:BAAALgAECgMJAwAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elishii:BAAALgADCgYJBgAAAA==.Elkanàh:BAAALgAFFAEJAgABLgAFFAMJCgAMAMIgAA==.Elleynle:BAAALgAECgUJEAAAAA==.Elunara:BAACLgAFFH8YAAIUAAQJbxrIBwBDAQAUAAQJbxrIBwBDAQAuAAQKf0wAAhQACQkEIbwCAPMCABQACQkEIbwCAPMCAAEuAAQKCQkhAAgA1h8A.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.Emptor:BAAALgAECgEJAQAAAA==.Emreezus:BAAALgAECgMJAwABLgAFFAQJHgAhAO4gAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.Enigmä:BAAALgADCgYJCgAAAA==.Enio:BAAALgAECgMJAwAAAA==.',
Er='Ericuh:BAABLgAECn8eAAMBAAYJsxKqXgAiAQABAAYJsxKqXgAiAQACAAEJjAdrpAAjAAAAAA==.',
Es='Escanör:BAAALgAECgYJEAABLgAECgkJIQAGAGQiAA==.Essekk:BAACLgAFFH8UAAIDAAUJrxsMPABXAQADAAUJrxsMPABXAQAuAAQKfy8AAgMACQklH2AWACMDAAMACQklH2AWACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Evodrak:BAAALgADCgYJBwAAAA==.Evokeeznutz:BAAALgAECgcJCQABLgAFFAQJCgAIANwZAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.Exploreswag:BAAALgAECgcJDwAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.',
['Eí']='Eír:BAAALgAECgUJBQABLgAECggJOAAaAOUdAA==.',
Fa='Fairyholy:BAAALgADCgIJAgAAAA==.Fallenchaos:BAAALgAECgYJBgAAAA==.Famjam:BAABLgAECn8UAAIhAAYJkxGSqgALAQAhAAYJkxGSqgALAQAAAA==.Fao:BAAALgAECgQJBQAAAA==.Fastrialimas:BAAALgAECgYJDAAAAA==.Fatpo:BAABLgAECn8kAAMaAAgJzSC6BgDiAgAaAAgJzSC6BgDiAgAOAAUJsCKLIwCMAQABLgAFFAQJDQAeAMQiAA==.Fayjhu:BAABLgAECn8mAAIDAAgJaAsChABUAQADAAgJaAsChABUAQAAAA==.',
Fe='Felwingz:BAAALgADCgEJAQAAAA==.Ferbos:BAAALgAECgIJAwAAAA==.Feylock:BAABLgAECn8UAAIJAAcJ7RBAjQAWAQAJAAcJ7RBAjQAWAQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgAECgYJBwAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAACLgAFFH8NAAIgAAQJqhtMEQBdAQAgAAQJqhtMEQBdAQAuAAQKfzIAAiAACQk9HvIJAG8CACAACQk9HvIJAG8CAAAA.',
Fr='Frigate:BAABLgAECn8YAAIDAAcJWgUS2QA/AQADAAcJWgUS2QA/AQAAAA==.Frihgate:BAABLgAECn8aAAISAAgJNhZ2MgDmAQASAAgJNhZ2MgDmAQAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frostmyface:BAAALgAFFAIJAwAAAA==.Frozenbeard:BAAALgAECgcJEwAAAA==.',
Fu='Fugarra:BAAALgAECgQJBQABLgAECgkJFQANAGYFAA==.Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAACLgAFFH8GAAIdAAMJSR7ZHgAdAQAdAAMJSR7ZHgAdAQAuAAQKfxYAAh0ACAl/Ic8OADsCAB0ACAl/Ic8OADsCAAAA.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgAECgcJCAAAAA==.Fuzi:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.Fuzybritches:BAAALgAECgEJAQABLgAECgcJCQAFAAAAAA==.',
Fy='Fyafya:BAAALgAFFAEJAQAAAA==.Fyah:BAABLgAECn8ZAAIhAAkJaSDhLAA0AgAhAAkJaSDhLAA0AgABLgAFFAcJFwAiAFgcAA==.Fyaza:BAAALgAECgUJBgAAAA==.',
Ga='Gaga:BAAALgAECgEJAQAAAA==.Gargamels:BAAALgAECgQJBgABLgAECgkJFQANAGYFAA==.Gariantel:BAAALgAECgMJCwAAAA==.Garleck:BAAALgAECgYJCwAAAA==.Garou:BAABLgAECn8jAAILAAgJOB7XDwBoAgALAAgJOB7XDwBoAgAAAA==.Gaygar:BAAALgADCgcJEwAAAA==.',
Ge='Geekylock:BAAALgAECgUJDgAAAA==.Geekymage:BAAALgAECgQJCAAAAA==.Geekyxgenome:BAAALgADCgEJAQAAAA==.Genesis:BAABLgAFFH8FAAIbAAMJbxv8bwD+AAAbAAMJbxv8bwD+AAAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgUJDQAAAA==.Gerttie:BAAALgAECgUJCAAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAcJLQAMAPQhAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAAALgAECggJEwAAAA==.Gorehammer:BAABLgAECn8qAAIbAAgJlxmHUAAAAgAbAAgJlxmHUAAAAgAAAA==.Gorto:BAAALgAECgEJAQAAAA==.',
Gr='Grassmoker:BAAALgAECgEJAwAAAA==.Gravediger:BAAALgAECgcJEQAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Grek:BAABLgAFFH8KAAIYAAQJ6iKGBwCTAQAYAAQJ6iKGBwCTAQAAAA==.Gridxx:BAABLgAECn8WAAMfAAcJDhPyKgBiAQAfAAcJDhPyKgBiAQAZAAEJkATQUAAfAAAAAA==.Grievex:BAABLgAECn9BAAIhAAkJ8wuEaQCCAQAhAAkJ8wuEaQCCAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.Grimblefritz:BAAALgADCgMJAwAAAA==.Gronthar:BAAALgADCgEJAQAAAA==.',
['Gî']='Gîgâbussy:BAAALgADCgIJAgAAAA==.',
Ha='Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgMJBAAAAA==.Hanyu:BAAALgAECggJCwAAAA==.Harkelem:BAAALgAECgkJAQAAAA==.Haydayy:BAAALgADCgYJBgAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healabae:BAAALgAECgkJCQABLgADCgYJBwAFAAAAAA==.Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAABLgAECn8bAAMaAAgJPBU5FwAAAgAaAAgJPBU5FwAAAgAMAAIJ4wMbYgBIAAAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Hemobloom:BAAALgAECgIJAgABLgAFFAQJHgAhAO4gAA==.Hemolock:BAACLgAFFH8GAAIJAAQJmgNhYgDlAAAJAAQJmgNhYgDlAAAuAAQKfyIAAwkABglpG+pRAJoBAAkABglpG+pRAJoBAAoAAQkAAHhPAAAAAAEuAAUUBAkeACEA7iAA.Hemostasis:BAACLgAFFH8eAAIhAAQJ7iDoGQB6AQAhAAQJ7iDoGQB6AQAuAAQKfyoABCEACAnQIr0nAEsCACEACAnQIr0nAEsCACMABAm8CSpiAJAAABUAAQksDmdKACsAAAAA.Herjä:BAABLgAECn84AAMaAAgJ5R3VDQBxAgAaAAgJ5R3VDQBxAgAMAAYJrRNgJQBpAQAAAA==.Hexmora:BAAALgAECgEJAgAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.',
Ho='Homeslice:BAAALgAECgUJBwAAAA==.Hoocha:BAAALgADCgYJBgABLgAFFAQJCgAIANwZAA==.Hoollymollyy:BAAALgAECgEJAQAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.Hotandcold:BAAALgAECgEJAgAAAA==.',
Hu='Hunterskillz:BAAALgADCgYJBgAAAA==.Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgIJAgAAAA==.Huun:BAABLgAECn84AAIiAAkJiB/AAwDuAgAiAAkJiB/AAwDuAgAAAA==.',
Hy='Hyasynthia:BAAALgAECgkJDgAAAA==.Hycindraeda:BAAALgAECgYJBgAAAA==.',
['Hú']='Húckleberry:BAAALgAECggJEAAAAA==.',
Ia='Iamnsfw:BAAALgAECgcJEgAAAA==.',
Ic='Icelcelance:BAABLgAFFH8IAAIDAAUJog+xUQAuAQADAAUJog+xUQAuAQAAAA==.',
Il='Illuminee:BAAALgAECgIJAgABLgAECgIJAgAFAAAAAA==.Illydan:BAABLgAECn8iAAMNAAkJFxtRFQCFAgANAAkJFxtRFQCFAgAWAAEJGAjBZwApAAAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn83AAIDAAkJPSC9EADjAgADAAkJPSC9EADjAgAAAA==.Impedup:BAAALgAECgUJBQAAAA==.',
In='Indigø:BAAALgAECgUJDgAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAFFAEJAgAFAAAAAA==.',
Ir='Irezufortips:BAAALgAECgcJCAABLgAECgkJFQANAGYFAA==.Ironhide:BAAALgAECgIJAgAAAA==.Ironshadow:BAAALgADCgEJAQAAAA==.Irrenadro:BAABLgAECn8WAAIhAAgJJw6+fQB+AQAhAAgJJw6+fQB+AQAAAA==.Irvainee:BAAALgAECgYJDAABLgAECgcJEQAFAAAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Ja='Jadechaos:BAAALgAECgEJAQAAAA==.Jadireux:BAAALgAECgYJEgAAAA==.Jaelia:BAAALgADCgEJAQAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jarnabas:BAAALgAECggJCgAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jiffypop:BAAALgADCgUJBQAAAA==.Jimboslice:BAAALgADCgcJBwAAAA==.Jimmyhoofa:BAAALgADCgkJCQAAAA==.Jingleparts:BAAALgAECgUJBQABLgAECgkJHwAaAIocAA==.',
Jo='Joes:BAABLgAECn8mAAMSAAcJ9hePVACNAQASAAcJ9hePVACNAQAEAAYJdQdsHAC2AAAAAA==.Jonesy:BAAALgAECgUJDAAAAA==.Jophiel:BAAALgADCgkJCwAAAA==.Jorath:BAAALgAECgUJBgABLgAECgkJFQANAGYFAA==.',
Ju='Juicygossip:BAAALgAECgYJBwAAAA==.Jujupowa:BAABLgAECn8bAAIhAAcJWgU4zADZAAAhAAcJWgU4zADZAAAAAA==.Junebug:BAAALgAECgQJBQAAAA==.Justicus:BAAALgADCgMJAwAAAA==.',
['Jë']='Jëssë:BAAALgAECgQJBAAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kagal:BAABLgAECn8WAAIiAAgJ3RExDwDSAQAiAAgJ3RExDwDSAQAAAA==.Kaidan:BAABLgAECn8oAAISAAkJpBIrQQDHAQASAAkJpBIrQQDHAQAAAA==.Kaipriest:BAAALgAECgQJBAAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kaledra:BAAALgAECgQJBAAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgQJBQAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAFFAMJCAAWAJUjAA==.Katanya:BAAALgAECgYJCwABLgAECgkJIQAIANYfAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8XAAISAAUJ5hdiIgBVAQASAAUJ5hdiIgBVAQAAAA==.Keftheals:BAAALgAECgkJCgAAAA==.Keiriline:BAABLgAECn8kAAMkAAcJvRbsDgBTAQAkAAcJvRbsDgBTAQAbAAEJYwDdeAEXAAAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAABLgAECn8hAAIiAAgJzhycEwD9AQAiAAgJzhycEwD9AQAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgYJCgAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.Khalysea:BAAALgADCgIJAgABLgAECgkJIQAIANYfAA==.',
Ki='Kiimari:BAAALgAECggJDAAAAA==.Killbreed:BAABLgAECn8oAAIZAAgJnCNyAwDCAgAZAAgJnCNyAwDCAgAAAA==.Kinkster:BAAALgAECgMJAwAAAA==.Kirinani:BAAALgAECgEJAQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knight:BAAALgAECgYJDAABLgAFFAQJDQAcABciAA==.Knuggz:BAABLgAECn8oAAILAAgJ8R40EgBPAgALAAgJ8R40EgBPAgAAAA==.',
Ko='Kolduna:BAAALgADCgUJBQAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgADCgkJEQAAAA==.',
Kr='Krestaul:BAAALgAECgcJCwAAAA==.',
Ku='Kurthalan:BAAALgAECgQJDAAAAA==.Kuumaneko:BAACLgAFFH8FAAIJAAMJrBc2XQDxAAAJAAMJrBc2XQDxAAAuAAQKfzYAAwkACQlbIdoHAAsDAAkACQlbIdoHAAsDAAoABgmvBwwxAPUAAAAA.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJEgAAAA==.Kyledh:BAACLgAFFH8RAAINAAQJpx+bIQB6AQANAAQJpx+bIQB6AQAuAAQKfzwAAw0ACQkjJlABAG8DAA0ACQkjJlABAG8DACUAAQluIf8jAGIAAAAA.Kyletotems:BAABLgAFFH8FAAIHAAMJPiVSBQBNAQAHAAMJPiVSBQBNAQAAAA==.Kyllgorre:BAAALgAECgEJAQAAAA==.Kynyine:BAAALgADCgcJCAAAAA==.',
La='Lancee:BAAALgAECgcJCAAAAA==.Landridan:BAAALgAECgMJAwAAAA==.Lanstoll:BAAALgAECgUJBAAAAA==.Lanthin:BAAALgADCggJEgAAAA==.Larzoe:BAAALgAECgYJCQABLgAECgkJIgAWAOojAA==.Larzoh:BAABLgAECn8iAAMWAAkJ6iOkAwBGAwAWAAkJ6iOkAwBGAwANAAMJSw6r0wBlAAAAAA==.Laudrup:BAAALgAECgEJAQAAAA==.Lawdhots:BAAALgAECgIJAgAAAA==.Laylaria:BAAALgADCgEJAQAAAA==.',
Le='Lee:BAAALgADCgYJBQABLgAFFAIJBwAbAK0gAA==.Legadiaus:BAAALgAECggJCgAAAA==.Lemonheads:BAABLgAECn85AAMMAAkJfRmUCQC8AgAMAAkJfRmUCQC8AgAOAAEJ4QEtagAjAAAAAA==.Lethargy:BAAALgAECgQJBAAAAA==.',
Li='Liaenara:BAAALgADCgYJCwAAAA==.Lidorila:BAAALgAECgMJAwAAAA==.Lightbranger:BAAALgADCgMJAwAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgcJCgABLgAECgYJEwAFAAAAAA==.Lilwiz:BAAALgAECgUJDwAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Linnxs:BAAALgAECgIJBAABLgAECgMJBgAFAAAAAA==.Linnxvx:BAAALgAECgMJBgAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgMJBQAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgAFAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwAFAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgAFAAAAAA==.Loxley:BAAALgAECgYJCgAAAA==.',
Ls='Lshaman:BAABLgAFFH8FAAIBAAMJ7BtgNQDuAAABAAMJ7BtgNQDuAAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAAALgAECgcJDwAAAA==.Lunahunter:BAAALgAECgEJAQAAAA==.Lunarcricket:BAAALgAECgUJCAABLgAECgkJNQAVAMwjAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwAFAAAAAA==.',
Ly='Lyncha:BAAALgAECgYJBgABLgAECgkJNQAVAMwjAA==.Lynchà:BAABLgAECn81AAIVAAkJzCMqAQA3AwAVAAkJzCMqAQA3AwAAAA==.Lynchá:BAAALgADCgIJAgAAAA==.Lynchä:BAAALgADCgEJAQABLgAECgkJNQAVAMwjAA==.',
Ma='Maakun:BAABLgAECn8dAAQaAAcJ3gxoOwBNAQAaAAcJ2gdoOwBNAQAOAAUJ8wcWQAD2AAAMAAQJHg2rOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJDgABLgAECgUJBgAFAAAAAA==.Madette:BAAALgADCggJCAABLgAFFAcJLQAMAPQhAA==.Mageapoug:BAAALgADCgcJBwAAAA==.Magia:BAAALgAECgEJAQAAAA==.Magmalance:BAAALgAECgYJCAABLgAECgYJFQANAOMPAA==.Maharahgha:BAAALgAECgEJAQAAAA==.Mahoragga:BAAALgADCgYJBgAAAA==.Mahzad:BAACLgAFFH8OAAIBAAUJgyGxCwDgAQABAAUJgyGxCwDgAQAuAAQKfyYAAwEABwljIzoYAFQCAAEABwljIzoYAFQCAAIABgmmDVJNAOMAAAAA.Maladi:BAAALgADCgkJJAAAAA==.Malfrun:BAABLgAECn8pAAMYAAkJLBYADwDjAQAYAAkJLBYADwDjAQALAAIJjQXwggBPAAAAAA==.Marinnite:BAAALgADCgYJDgAAAA==.Markzugrberg:BAAALgADCgkJCQAAAA==.Marox:BAACLgAFFH8IAAIDAAQJwgqCXQAWAQADAAQJwgqCXQAWAQAuAAQKfxgAAgMACQldHXZDAG4CAAMACQldHXZDAG4CAAAA.Marrøwgar:BAAALgAECgUJBQABLgAECgYJFQANAOMPAA==.Marshmellows:BAAALgAECgYJBgABLgAECgYJHgABALMSAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAACLgAFFH8cAAIJAAUJxiT6HQCcAQAJAAUJxiT6HQCcAQAuAAQKfyMAAwkACQmGJEoVANUCAAkACAmGJEoVANUCAAoAAQkAANtVAG0AAAAA.Matooka:BAABLgAECn8kAAISAAkJKQ1NQwDAAQASAAkJKQ1NQwDAAQAAAA==.Maynji:BAAALgAECgMJAwAAAA==.Mayushi:BAAALgAECgYJCQAAAA==.',
Mc='Mcthugger:BAAALgAECgEJAQABLgAFFAIJBQAhADgIAA==.',
Me='Meencurry:BAABLgAECn8kAAIDAAgJghUZWwC0AQADAAgJghUZWwC0AQAAAA==.Megozugzug:BAAALgAFFAEJAgAAAA==.Meyneth:BAAALgAECgQJCAAAAA==.',
Mi='Mikaì:BAAALgAECgkJEgAAAA==.Mikehawkener:BAAALgAECgYJDwAAAA==.Mirlone:BAAALgAECgIJAgAAAA==.Misleading:BAAALgAECgUJEwAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Missdead:BAAALgAECgEJAQAAAA==.Mistfisting:BAACLgAFFH8FAAIeAAMJURQfLwCxAAAeAAMJURQfLwCxAAAuAAQKfxQAAh4ABwmEHlUeAP8BAB4ABwmEHlUeAP8BAAAA.',
Mo='Moderato:BAAALgAECgkJDgAAAA==.Moelleri:BAABLgAECn8dAAIbAAgJaBlpTwDCAQAbAAgJaBlpTwDCAQAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgUJBgAFAAAAAA==.Molodeath:BAAALgAECgUJBQAAAA==.Moneymage:BAAALgAECgcJCwAAAA==.Monkgroom:BAACLgAFFH8WAAIeAAUJ0QsIIAAaAQAeAAUJ0QsIIAAaAQAuAAQKfx0AAx4ACQmaFA8XAAkCAB4ACQmaFA8XAAkCABwABgnyCto5ADYBAAAA.Monsignor:BAAALgAECgIJCgAAAA==.Montra:BAACLgAFFH8HAAIUAAMJ6g7JFAC4AAAUAAMJ6g7JFAC4AAAuAAQKfzMAAxQACQn6HEoFAJsCABQACQn6HEoFAJsCABkABQkCCf4eAOsAAAAA.Mordach:BAAALgAECgEJAgAAAA==.Moreilira:BAAALgAECgYJEQAAAA==.Mornshield:BAABLgAECn8fAAMhAAYJWxSmkQBZAQAhAAYJIxCmkQBZAQAVAAUJUxMIJgDZAAABLgAECgkJFQANAGYFAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motorinkashi:BAABLgAECn8aAAMPAAkJ5h6VBwAwAwAPAAkJ5h6VBwAwAwAUAAMJFw+HQQB1AAAAAA==.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAABLgAECn8aAAIYAAgJoRSzGABgAQAYAAgJoRSzGABgAQAAAA==.Muddthir:BAAALgAECgQJBAABLgAECggJGgAYAKEUAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCwAAAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwAhANocAA==.',
Na='Nahaine:BAAALgADCggJCAAAAA==.Nazrra:BAABLgAECn8bAAIYAAkJIxRkEAACAgAYAAkJIxRkEAACAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgAECgEJAQAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Nenad:BAAALgADCgEJAQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nerodic:BAAALgADCgYJBgABLgAFFAQJEwAbAMgYAA==.Nestaah:BAAALgAFFAIJBAAAAA==.Nettra:BAAALgAECgIJCgAAAA==.Newtnewt:BAAALgAECgUJBgAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nicneven:BAAALgADCgkJCQAAAA==.Nininbrew:BAAALgAECgEJAwABLgAECgYJDQAFAAAAAA==.Nirath:BAABLgAECn86AAIDAAkJEhbVMQA6AgADAAkJEhbVMQA6AgAAAA==.',
No='Nobainer:BAAALgADCgYJCwAAAA==.Noed:BAAALgAECgMJBgAAAA==.Nohkana:BAAALgAECgEJAQAAAA==.Nohkano:BAABLgAECn8zAAIdAAkJliUtAQBaAwAdAAkJliUtAQBaAwAAAA==.Nokinkshame:BAAALgADCggJCQABLgAECgkJHwAaAIocAA==.Nokt:BAAALgADCgQJBAAAAA==.Noobymonk:BAAALgAECggJEwAAAA==.Noralise:BAAALgAECgYJEwAAAA==.Northerndk:BAABLgAECn8WAAIbAAcJKgUF0QDPAAAbAAcJKgUF0QDPAAAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgQJCAAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.Nutthunter:BAAALgAECgEJAwAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAIDAAgJVhTDbAD8AQADAAgJVhTDbAD8AQAAAA==.',
Oa='Oakmain:BAAALgAECgUJBQAAAA==.',
Oc='Octavarium:BAABLgAECn8hAAIeAAgJExwPEwBjAgAeAAgJExwPEwBjAgAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.Odinspriest:BAAALgADCgcJBwAAAA==.Odinsvulpera:BAAALgADCgYJBwAAAA==.',
Oe='Oennomaus:BAAALgAECgUJBgAAAA==.',
Of='Offspec:BAAALgAECgEJAgAAAA==.',
Oh='Ohyshii:BAAALgAECgMJBQAAAA==.',
Ol='Olorinziln:BAAALgAECgYJBgAAAA==.',
On='Oneshothel:BAABLgAECn8XAAISAAYJ5xpbXAB3AQASAAYJ5xpbXAB3AQAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwAhANocAA==.',
Or='Orcpeon:BAAALgAECgYJDQABLgAECggJNgAhAKAdAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAAALgAECgYJEgABLgAECgkJHwAaAIocAA==.Overdoze:BAAALgADCgcJDQAAAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Paichan:BAAALgAECgEJAQAAAA==.Palakazam:BAAALgAECgEJAQAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgADCgYJCwAAAA==.Pancaked:BAAALgAECggJEQABLgAECgkJHwAaAIocAA==.Pantheons:BAAALgADCgIJAwAAAA==.Paradon:BAAALgADCgEJAQAAAA==.Paradox:BAAALgAECgQJBAABLgAFFAUJFQAZAA0jAA==.Parsi:BAACLgAFFH8FAAIlAAIJSxiGCQCNAAAlAAIJSxiGCQCNAAAuAAQKfxYAAiUABwnwGBwOAFQBACUABwnwGBwOAFQBAAAA.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Penut:BAAALgAECgEJAQAAAA==.Perritax:BAABLgAECn8iAAIDAAcJdhEPgQBbAQADAAcJdhEPgQBbAQAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwAAAA==.Phoebelyria:BAAALgAECgYJEwAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgAFAAAAAA==.',
Pi='Pickelz:BAAALgADCgMJAwAAAA==.Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgUJCQAAAA==.Pingdoo:BAAALgAECgIJAwAAAA==.Piptip:BAAALgADCgcJBwAAAA==.Pizzaparty:BAAALgAECgQJAwABLgAECgkJHwAaAIocAA==.',
Po='Pofat:BAABLgAFFH8NAAIeAAQJxCIaFACPAQAeAAQJxCIaFACPAQAAAA==.Polis:BAABLgAECn82AAMhAAgJoB2MKwA6AgAhAAgJoB2MKwA6AgAVAAEJrBH9RgA1AAAAAA==.Pomol:BAAALgAECgcJEgAAAA==.Pomoly:BAAALgAECgIJAwAAAA==.Poppafury:BAABLgAECn8ZAAIYAAcJJBVaGABkAQAYAAcJJBVaGABkAQAAAA==.Potent:BAABLgAECn8gAAMbAAgJ4RHvdQBjAQAbAAgJ4RHvdQBjAQAmAAQJbQaPOgBvAAAAAA==.Poubear:BAAALgAECgYJCAABLgAECgkJFQANAGYFAA==.Pougadina:BAAALgAECgYJCAABLgAFFAQJDQAeAMQiAA==.',
Pr='Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAACLgAFFH8IAAIbAAMJ1gh2lADEAAAbAAMJ1gh2lADEAAAuAAQKfxgAAxsACAn1FlVTALYBABsACAn1FlVTALYBACYAAQlLBH5PABcAAAAA.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAAALgAECgcJEgABLgAECgkJFQANAGYFAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Qi='Qizzle:BAAALgADCgMJAwAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAIhAAYJYxbTigBlAQAhAAYJYxbTigBlAQAAAA==.Ramshunter:BAABLgAECn8fAAMSAAkJFiFcBwAaAwASAAkJFiFcBwAaAwAEAAIJ4xGjMgA+AAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgAECgQJCAAAAA==.Ratnob:BAABLgAECn8vAAIbAAkJbRofJQBcAgAbAAkJbRofJQBcAgAAAA==.Ravnaar:BAAALgAECgkJDwAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.',
Re='Reddemon:BAAALgAECgEJAQABLgAFFAQJCgAYAOoiAA==.Redstraw:BAAALgADCgYJBwAAAA==.Relda:BAAALgAFFAIJAwAAAA==.Remye:BAAALgAECgkJCQAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Rennshi:BAACLgAFFH8IAAIWAAMJlSPPDQAWAQAWAAMJlSPPDQAWAQAuAAQKfyEAAhYACQlBJAgEADsDABYACQlBJAgEADsDAAAA.Retpally:BAABLgAFFH8QAAIYAAcJ7hR4BADhAQAYAAcJ7hR4BADhAQAAAA==.Reyikrat:BAAALgAECgQJCAAAAA==.Rezmee:BAACLgAFFH8IAAIbAAMJJSVHYgAZAQAbAAMJJSVHYgAZAQAuAAQKfxgAAhsACQmIIxIRANMCABsACQmIIxIRANMCAAAA.',
Rh='Rheaf:BAAALgAECgYJCQAAAA==.',
Ri='Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8WAAIDAAcJPxGIvgBmAQADAAcJPxGIvgBmAQAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rolexiós:BAAALgADCgcJBwAAAA==.Rosario:BAACLgAFFH8RAAMiAAQJah5JCAB3AQAiAAQJah5JCAB3AQAEAAIJOQ1KHwCZAAAuAAQKfz0AAyIACQm/I7ABADMDACIACQl6IrABADMDAAQACAmhIakNANgCAAAA.Royfan:BAAALgAECgQJBAAAAA==.',
Ry='Ryotwar:BAAALgAECgEJAQAAAA==.Rythmatic:BAACLgAFFH8IAAIgAAMJ6yS7GAAzAQAgAAMJ6yS7GAAzAQAuAAQKfysAAyAACQm/JacBAEYDACAACQm/JacBAEYDACcABgkNHhcIALkBAAAA.Ryvenox:BAAALgADCgcJBwAAAA==.',
['Ré']='Rénae:BAAALgAECgkJAgABLgAECgkJCAAFAAAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Saccharine:BAABLgAECn8hAAMMAAkJCBdBDwBcAgAMAAkJCBdBDwBcAgAOAAEJdAAWbQAHAAAAAA==.Sakieri:BAABLgAECn9BAAIOAAkJMiC2BQDhAgAOAAkJMiC2BQDhAgAAAA==.Salinomycin:BAABLgAECn8UAAIPAAYJ5wcpcQDPAAAPAAYJ5wcpcQDPAAAAAA==.Saltyaf:BAAALgADCgMJAwAAAA==.Saltymcnalty:BAAALgAECgEJAQAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sandolorian:BAAALgAECgcJCwAAAA==.Sandordel:BAAALgADCgYJDQAAAA==.Sangan:BAABLgAECn8fAAIDAAcJRh4uOwAWAgADAAcJRh4uOwAWAgAAAA==.Sanguini:BAABLgAECn8qAAIDAAkJOBicNQAqAgADAAkJOBicNQAqAgAAAA==.Sathari:BAAALgAECgQJCAAAAA==.',
Sc='Schmelzen:BAABLgAFFH8LAAIDAAUJUBXMSgA5AQADAAUJUBXMSgA5AQAAAA==.Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAFFAEJAQABLgAFFAEJAgAFAAAAAA==.Selaris:BAAALgAECgYJEQAAAA==.Selathviala:BAAALgADCgMJBQAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8YAAMRAAcJ4h3JAQCDAQAQAAYJYhtNDwDCAQARAAQJmhvJAQCDAQAuAAQKfywAAxEACQnJIsEBAC8DABEACAlJI8EBAC8DABAACAlUIxAJAK8CAAAA.Sergregorsly:BAAALgAECggJCAAAAA==.',
Sh='Shadowblitzx:BAAALgAECgUJEAAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAFFAQJDQAgAKobAA==.Shangan:BAAALgAECgEJAgAAAA==.Shapestalker:BAAALgADCgcJCAAAAA==.Sharana:BAAALgAECgQJCAAAAA==.Shazzie:BAAALgADCgYJCwAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgAECgMJBwAAAA==.Shirrazaha:BAAALgADCgcJBwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgABLgAFFAQJDQATAJkgAA==.',
Si='Silaris:BAAALgADCgMJBgAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Sinnur:BAAALgAECgQJCQAAAA==.Sinsear:BAAALgADCgYJBgAAAA==.',
Sk='Skeezer:BAABLgAFFH8KAAIIAAQJ3BloAgBjAQAIAAQJ3BloAgBjAQAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizzie:BAAALgAECgYJDQAAAA==.Slizziore:BAAALgAECgEJAgAAAA==.Slizzle:BAAALgAECgEJAQAAAA==.Slizzley:BAAALgAECgEJAgAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.',
Sm='Smackdiver:BAAALgADCgYJAwAAAA==.Smarfus:BAAALgAECgYJCQABLgAFFAQJCgAYAOoiAA==.Smilingdemon:BAAALgAECgQJBQAAAA==.Smilingp:BAAALgADCgkJDwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAABLgAECn8UAAIcAAYJdwPeXACIAAAcAAYJdwPeXACIAAAAAA==.Snarge:BAACLgAFFH8SAAIHAAYJ2hQvAwCBAQAHAAYJ2hQvAwCBAQAuAAQKfxkABAcACQkpGSAKADACAAcACQkpGSAKADACAAEABQlqCA+CALkAAAIAAQkjEsaDADsAAAAA.Sneaktee:BAAALgAECgMJBAABLgAECggJGAAbAK8cAA==.',
So='Soone:BAAALgAECgkJAQAAAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Sparkydrac:BAAALgAECgYJBgABLgAECgYJFQANAOMPAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spness:BAAALgAECgUJBQAAAA==.Spunky:BAAALgAECgQJBwAAAA==.',
Sq='Squeaksune:BAAALgADCgcJCAAAAA==.Squiish:BAABLgAECn8aAAIDAAcJYQ2cjgA/AQADAAcJYQ2cjgA/AQAAAA==.',
Sr='Srorcalot:BAABLgAECn8UAAIbAAcJ7QwajQA2AQAbAAcJ7QwajQA2AQABLgAECgkJFQANAGYFAA==.',
St='Steppedon:BAAALgAECgYJEwAAAA==.Stingerai:BAABLgAECn8cAAISAAkJJyCXIABNAgASAAkJJyCXIABNAgABLgAECgkJLQAUAPQeAA==.Stingeret:BAAALgADCgMJAwABLgAECgkJLQAUAPQeAA==.Stingerge:BAAALgAECgMJBAABLgAECgkJLQAUAPQeAA==.Stormweaverr:BAAALgAFFAEJAQABLgAFFAQJCgAYAOoiAA==.',
Su='Sunbeamer:BAAALgAECgUJDAAAAA==.Sureman:BAAALgAECgMJBQAAAA==.Suun:BAAALgAECgQJBAAAAA==.',
Sw='Swaggie:BAAALgADCgQJBgAAAA==.Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylentsniper:BAAALgAECgYJBgABLgAECgkJFQANAGYFAA==.Sylvesters:BAAALgADCgcJBwABLgAECgUJBgAFAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
['Sá']='Sága:BAAALgAECgEJAQAAAA==.',
Ta='Tacosalad:BAAALgAECgcJCwABLgAECgkJHwAaAIocAA==.Taellas:BAAALgADCgMJAwAAAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Talinas:BAAALgADCgYJBgAAAA==.Tamb:BAABLgAECn8gAAIPAAYJwRTFTQBFAQAPAAYJwRTFTQBFAQAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tankndspank:BAAALgADCgYJBgAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Tark:BAAALgADCgYJBwAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwAFAAAAAA==.Tauntisoff:BAAALgADCgMJAwAAAA==.',
Tc='Tchittykitty:BAAALgAECgMJAwAAAA==.',
Te='Tecomonk:BAAALgADCgIJAgAAAA==.Tedious:BAAALgAECgYJEwAAAA==.Teehuntee:BAAALgAECgYJBwABLgAECggJGAAbAK8cAA==.Teepal:BAAALgAECgcJCwABLgAECggJGAAbAK8cAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAABLgAECn8kAAIHAAcJax+bCQAJAgAHAAcJax+bCQAJAgAAAA==.Teribullduce:BAACLgAFFH8SAAIiAAQJXhmODQBMAQAiAAQJXhmODQBMAQAuAAQKf1cAAiIACQklH04EAN8CACIACQklH04EAN8CAAAA.Terscheckii:BAAALgAFFAIJBAAAAA==.',
Th='Theslimer:BAABLgAECn8aAAMSAAkJShqUHwBTAgASAAkJShqUHwBTAgAEAAYJpQqSVQDzAAAAAA==.Thesukuna:BAAALgAECgUJBwAAAA==.Thingol:BAAALgADCgcJCwAAAA==.Thormor:BAACLgAFFH8tAAIMAAcJ9CGoAQAhAgAMAAcJ9CGoAQAhAgAuAAQKfy4ABAwACQk8JPsAAJoDAAwACQk8JPsAAJoDABoABwnoHiMWACwCAA4ABQmVHp80AEUBAAAA.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAACLgAFFH8FAAMhAAIJOAhlhgB+AAAhAAIJOAhlhgB+AAAVAAEJvAj+FQAuAAAuAAQKfzIAAyEACQntHGIgAG8CACEACQntHGIgAG8CABUAAgmMDpg3AGYAAAAA.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAABLgAECn8lAAMVAAgJfgybHAAXAQAVAAgJfgybHAAXAQAhAAMJHgoB/gCYAAAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tidy:BAAALgAECgEJAQAAAA==.Tigg:BAAALgAECgMJBAAAAA==.Tiimmyy:BAAALgAECgYJDAAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDwAAAA==.Tinkertotem:BAAALgADCgkJCQAAAA==.Tinyandcute:BAAALgAECgMJAwABLgAECgkJHwAaAIocAA==.Tiravana:BAAALgAECgIJAgAAAA==.',
To='Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgAECgQJBAABLgAECggJGwAIACkTAA==.',
Tr='Trebuchet:BAABLgAECn8VAAMbAAgJsw+BXQCbAQAbAAgJsw+BXQCbAQAkAAMJRAXHEQB0AAAAAA==.Treefrog:BAAALgADCgkJDAAAAA==.Treeshine:BAAALgAECgcJAQABLgAECggJGAANANkVAA==.Trtmiles:BAAALgAECgcJDwAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAABLgAECn8gAAIDAAgJNCKpHQCVAgADAAgJNCKpHQCVAgAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgQJDAAAAA==.',
Ub='Ubeenbained:BAABLgAECn8sAAIWAAgJoBDVGgCGAQAWAAgJoBDVGgCGAQAAAA==.',
Uh='Uhaw:BAAALgAECgYJBgAAAA==.',
Un='Unlock:BAABLgAECn8XAAISAAkJFhjuIwA8AgASAAkJFhjuIwA8AgAAAA==.',
Ur='Urgmathron:BAABLgAECn8dAAIVAAcJ7SL9BwBAAgAVAAcJ7SL9BwBAAgAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Valadashora:BAAALgAECgEJAQAAAA==.Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8XAAMBAAYJNwOOIABEAQABAAYJNwOOIABEAQACAAQJnRKgDAAhAQAuAAQKfyUAAwIACQm8IKgIAMACAAIACQm8IKgIAMACAAEAAQlsGQ22AEEAAAAA.Vanthyle:BAAALgAECgQJBAAAAA==.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgAECgQJDgAAAA==.',
Vd='Vdr:BAAALgADCgEJAgAAAA==.',
Ve='Velantheron:BAAALgAECgYJDQAAAA==.Velosityy:BAAALgAECgQJBQAAAA==.Vezrx:BAAALgAFFAIJAwAAAA==.',
Vi='Vinsmoke:BAAALgAECgYJEgAAAA==.Vitanimm:BAAALgADCgIJAwAAAA==.Vitiate:BAAALgAECgYJBgAAAA==.',
Vo='Voinox:BAAALgADCgcJDQABLgADCgcJEwAFAAAAAA==.Volcanoez:BAAALgAECgQJDwAAAA==.',
Vr='Vrezor:BAAALgAECgQJEAAAAA==.',
Vy='Vyolnc:BAAALgAECgQJCAAAAA==.Vyrexiona:BAABLgAECn8YAAMQAAcJ2BmDGAAMAgAQAAcJ2BmDGAAMAgARAAEJtwIURgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgcJDAAAAA==.',
Wa='Warorgen:BAAALgADCgcJDAAAAA==.Warthelian:BAAALgADCgcJBwABLgAECgYJFwASAOcaAA==.',
Wh='Whiskeytf:BAAALgADCgEJAQAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAIhAAgJ2hwnJQCSAgAhAAgJ2hwnJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECggJEQAAAA==.',
Wo='Wokthisway:BAAALgAECgQJCAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wreck:BAAALgADCgYJBgABLgAECgEJEgAFAAAAAA==.',
Wy='Wych:BAABLgAECn8VAAMVAAYJBhexIAD0AAAhAAYJvRW1nwAcAQAVAAQJBRWxIAD0AAABLgAECggJIAAKAO4eAA==.Wynain:BAAALgADCgUJBQAAAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAAALgAECgYJEwAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yappor:BAAALgAECggJDgAAAA==.',
Ye='Yekteniya:BAAALgAECgYJCQAAAA==.Yerrback:BAAALgAECgQJBgABLgAECgUJCQAFAAAAAA==.',
Yi='Yibbers:BAAALgADCgIJAgAAAA==.Yiimmyy:BAAALgAECgIJAwAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yunô:BAAALgAECgEJAQAAAA==.Yur:BAAALgADCgcJDAABLgAECgkJIQAGAGQiAA==.Yutch:BAAALgAECgYJEAAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAAALgAECgcJEQAAAA==.Zakkydrakky:BAABLgAECn8iAAMoAAkJIQ0UFgBZAQAoAAgJLg0UFgBZAQAQAAYJPggrUwC9AAAAAA==.Zani:BAAALgAECgIJAgAAAA==.Zarashara:BAABLgAECn8lAAMdAAgJFBTDKABaAQAdAAcJERbDKABaAQAcAAgJcQgpNAAdAQAAAA==.',
Ze='Zeddoc:BAEALgADCggJCAABLgAECgMJBQAFAAAAAA==.Zedward:BAEALgAECgMJBQAAAA==.Zelta:BAAALgADCgkJEwAAAA==.Zerise:BAAALgAECgUJCwAAAA==.',
Zo='Zolidus:BAAALgAECgYJCgAAAA==.Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAFFAEJAgAFAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8jAAIhAAkJKBKgXwCYAQAhAAkJKBKgXwCYAQAAAA==.Zun:BAAALgAECggJDQAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Èz']='Èzili:BAAALgAECgYJCwAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMbAAgJRRRZVgDuAQAbAAgJ/BJZVgDuAQAkAAUJxAwWHgCpAAAAAA==.',
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
