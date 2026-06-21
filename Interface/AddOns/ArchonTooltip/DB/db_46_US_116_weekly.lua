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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Mage-Frost','Hunter-Marksmanship','Unknown-Unknown','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Priest-Discipline','DemonHunter-Devourer','Priest-Shadow','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','DeathKnight-Unholy','Mage-Arcane','Druid-Guardian','Monk-Mistweaver','Priest-Holy','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Rogue-Subtlety','Hunter-Survival','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAABLgAECn8eAAMBAAgJUQzyWwBJAQABAAgJUQzyWwBJAQACAAIJRAiolABLAAAAAA==.Aaramis:BAACLgAFFH8OAAIBAAMJtQ1eVwCfAAABAAMJtQ1eVwCfAAAuAAQKfzkAAgEACQmeGbIiAD4CAAEACQmeGbIiAD4CAAAA.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ac='Achin:BAAALgADCgUJBQAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAABLgAECn8UAAIDAAgJEwRMxAADAQADAAgJEwRMxAADAQAAAA==.',
Ag='Aggrodk:BAAALgAECgIJAgAAAA==.',
Ah='Ahchu:BAAALgAECgIJAgAAAA==.Ahiru:BAAALgAECgMJAwAAAA==.',
Ai='Aidoffhealer:BAAALgAECgUJCwAAAA==.',
Al='Alariah:BAAALgAFFAMJBwAAAQ==.Alaín:BAABLgAECn8jAAIEAAgJuBj5CwCmAQAEAAgJuBj5CwCmAQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgAFAAAAAA==.Aldoraline:BAAALgADCgQJBgAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQABLgAECgEJAgAFAAAAAA==.Alystair:BAAALgADCgQJCAABLgAECgkJIQAGAGQiAA==.',
Am='Ambellina:BAAALgAECgYJDgAAAA==.Ampse:BAAALgAECgUJCAAAAA==.Amzy:BAAALgADCgYJCQABLgAECgEJAQAFAAAAAA==.',
An='Anaria:BAAALgAECggJEAAAAA==.Andirn:BAAALgAECggJDwAAAA==.Angbu:BAABLgAECn8iAAMHAAcJQRcZFQBsAQAHAAcJQRcZFQBsAQACAAEJoARgkQAmAAAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Aphadiri:BAAALgAECgMJBAAAAA==.Apinkninja:BAACLgAFFH8FAAIDAAMJDgyajQC+AAADAAMJDgyajQC+AAAuAAQKfycAAgMABwkbGuN0AJABAAMABwkbGuN0AJABAAAA.',
Ar='Aranyssa:BAABLgAECn8hAAQIAAkJ1h8TCwCsAQAIAAYJhSATCwCsAQAJAAYJ3hGPrQDoAAAKAAQJLhptIQCjAAAAAA==.Arch:BAAALgAECgIJAgABLgAFFAYJHQAJAB4lAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAABLgAFFH8JAAILAAMJAQuAOwDDAAALAAMJAQuAOwDDAAAAAA==.Ardur:BAAALgAECgMJAwAAAA==.Ark:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Arkork:BAAALgAECgEJAgAAAA==.Arnøld:BAABLgAFFH8GAAIMAAMJ5gkfNwCuAAAMAAMJ5gkfNwCuAAAAAA==.Arruna:BAABLgAECn8XAAINAAcJTRGejgADAQANAAcJTRGejgADAQAAAA==.Artorìas:BAAALgADCgkJCwABLgAECgkJIQAGAGQiAA==.',
As='Asham:BAACLgAFFH8FAAIMAAMJtgcrNwCuAAAMAAMJtgcrNwCuAAAuAAQKf0QAAwwACQmkEqIVAC0CAAwACQmkEqIVAC0CAA4AAgnNCw5yAF0AAAAA.Ashenbloom:BAABLgAECn8nAAIPAAgJignAXQAdAQAPAAgJignAXQAdAQAAAA==.Asherin:BAAALgADCgYJBgAAAA==.Asiago:BAABLgAECn8XAAMQAAkJ4BIgLQBYAQAQAAkJ4BIgLQBYAQARAAEJRge0PwAxAAAAAA==.Aspect:BAABLgAECn8hAAMGAAkJZCKLAAARAwAGAAkJZCKLAAARAwADAAEJWRLEYAE/AAAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgAECgQJBgAAAA==.',
Av='Avacúma:BAAALgAECgIJAwAAAA==.Avvalethra:BAABLgAECn9FAAMSAAkJeB4HFQCrAgASAAkJeB4HFQCrAgAEAAgJqg3XOwBwAQAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgcJDAAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAkJIQARACoeAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Babyball:BAAALgAECggJDAAAAA==.Bachshots:BAABLgAFFH8OAAISAAUJvxG0QgAoAQASAAUJvxG0QgAoAQAAAA==.Backstabbath:BAAALgAECgYJBgABLgAFFAIJBQASAOAFAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgYJDgABLgAFFAQJCQATAHwQAA==.Bainesaur:BAAALgADCggJDQAAAA==.Bainey:BAAALgADCgIJAgABLgAECgMJAwAFAAAAAA==.Bananataffy:BAABLgAECn8bAAIPAAcJWhRVPACiAQAPAAcJWhRVPACiAQAAAA==.Barackoshama:BAABLgAECn8eAAICAAkJAxwaHwDqAQACAAkJAxwaHwDqAQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Basedween:BAAALgADCgcJGAAAAA==.Batialexism:BAAALgADCgYJCwAAAA==.Battlescars:BAAALgAFFAIJAgAAAA==.Baw:BAABLgAECn88AAMDAAkJ6R6+GQC/AgADAAkJ6R6+GQC/AgAUAAMJFwmTFQBvAAAAAA==.',
Be='Bearelf:BAAALgAECgMJAwAAAA==.Bearlinwall:BAABLgAECn8eAAIVAAYJARLYLAD8AAAVAAYJARLYLAD8AAAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Beladori:BAAALgAECgMJAwAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.Bews:BAABLgAFFH8GAAIWAAMJCRpwMwDgAAAWAAMJCRpwMwDgAAAAAA==.',
Bi='Bigbuns:BAAALgAECgEJAQABLgAECgkJHwAXAIocAA==.Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigdumbo:BAAALgAECgQJBQABLgAFFAMJBQABAOwbAA==.Bigskydh:BAAALgAECgYJEAAAAA==.Bigskymage:BAAALgAFFAIJAwAAAA==.Bigskymoney:BAAALgAFFAMJAwAAAA==.Billybones:BAABLgAECn8aAAITAAgJWwYpwgD7AAATAAgJWwYpwgD7AAAAAA==.Bip:BAAALgADCgEJAQAAAA==.Birde:BAAALgADCgcJBwABLgADCggJDQAFAAAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAECgkJFAABAI4WAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECggJJQAYAH4MAA==.Bladedozzer:BAAALgAECggJCwAAAA==.Blindinglite:BAACLgAFFH8TAAIZAAQJNB+xCAB9AQAZAAQJNB+xCAB9AQAuAAQKfyUAAhkACAl7Ir4OADoCABkACAl7Ir4OADoCAAAA.Blindtoast:BAAALgAECgIJAgAAAA==.Blkpriest:BAAALgAECgIJAwAAAA==.Bloodhaze:BAACLgAFFH8OAAIZAAQJ2yJwCACAAQAZAAQJ2yJwCACAAQAuAAQKfyAAAhkACQmjHxgLAK8CABkACQmjHxgLAK8CAAAA.Bloodyfel:BAAALgAECgEJAQAAAA==.Blorp:BAACLgAFFH8YAAINAAQJihhUQgAhAQANAAQJihhUQgAhAQAuAAQKfx4AAw0ACAnfHMwlAHACAA0ACAnfHMwlAHACABoAAQlnHlcrAFUAAAAA.',
Bo='Bodizzle:BAAALgAECgEJAwAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgQJCQAAAA==.Borestus:BAABLgAECn8XAAIbAAcJQQ7ongA5AQAbAAcJQQ7ongA5AQAAAA==.Bouldur:BAABLgAECn8ZAAQLAAYJvArsWADrAAALAAYJJwnsWADrAAAcAAQJLAjhTwCTAAAdAAEJzgKqYQAWAAAAAA==.Bownystark:BAABLgAECn8eAAIEAAcJCCJHFQCIAgAEAAcJCCJHFQCIAgAAAA==.Bozz:BAAALgAECgQJBQAAAA==.',
Br='Brickingit:BAAALgAECgYJCwAAAA==.Brieter:BAAALgAECgcJDAABLgAECgkJFwAQAOASAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokendrako:BAABLgAFFH8GAAIVAAQJXQT8IwCLAAAVAAQJXQT8IwCLAAAAAA==.Brokikobo:BAAALgADCggJCwAAAA==.Broly:BAAALgAECgEJAQAAAA==.Bromthelian:BAAALgADCgkJCQABLgAECgcJGQASAOcYAA==.Broughston:BAAALgAECgEJAQAAAA==.Brutusx:BAABLgAECn8kAAISAAkJIw6QTAC8AQASAAkJIw6QTAC8AQAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAABLgAECn8nAAMVAAgJpCAwBwCEAgAVAAgJpCAwBwCEAgAeAAMJwQRORABTAAAAAA==.Burntcring:BAAALgAECgUJCwAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJDgAAAA==.',
Bx='Bxxberry:BAABLgAECn8ZAAQJAAcJ2wS4yQC9AAAJAAYJfQW4yQC9AAAIAAQJBwLFMABcAAAKAAMJPwO7NQBMAAAAAA==.',
Ca='Calari:BAAALgADCgEJAQAAAA==.Calculated:BAAALgAECgYJCAABLgAECgkJHwAXAIocAA==.Camipriest:BAAALgAECgEJAQAAAA==.Camishami:BAAALgADCgMJAwAAAA==.Cara:BAAALgAFFAMJBAABLgAFFAUJEgATAOolAA==.Carllina:BAAALgAECgYJBgAAAA==.Carmane:BAAALgAECgUJBQAAAA==.Casstyelle:BAAALgAECgQJCAABLgAECggJGwAIACkTAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgUJCgABLgAECgkJIQAIANYfAA==.Cet:BAAALgAECgQJBAABLgAECgkJIQAGAGQiAA==.Cexiback:BAAALgAFFAMJBAAAAA==.',
Ch='Chairon:BAAALgAECgQJBAABLgAFFAMJAwAFAAAAAA==.Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheebsz:BAAALgAECgUJBQAAAA==.Cheesus:BAAALgAECgcJDAABLgAECgkJFwAQAOASAA==.Chicharon:BAAALgAECgUJDwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECgkJHwAXAIocAA==.Chipsnsalsa:BAAALgAECgQJBAABLgAECgkJHwAXAIocAA==.Chocoriffic:BAABLgAECn8fAAIXAAkJihxjCwCwAgAXAAkJihxjCwCwAgAAAA==.Chokoballs:BAAALgAECgEJAQABLgAFFAMJCAATABsRAA==.Chokoballz:BAABLgAECn8fAAMfAAgJgR1LEABIAgAfAAgJoxxLEABIAgAgAAUJ3BrSMgA1AQABLgAFFAMJCAATABsRAA==.Churva:BAAALgAECgEJAQABLgAECgkJGgANAHwJAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAACLgAFFH8KAAMVAAMJhR9nDwAPAQAVAAMJhR9nDwAPAQAeAAEJHAvDIAA3AAAuAAQKfy4AAxUACQlJHzkEANcCABUACQlJHzkEANcCAB4AAQnEEX1SADQAAAAA.Coldbrewz:BAAALgAECgYJDwAAAA==.Conalbegle:BAAALgAECgUJCwAAAA==.Condensation:BAAALgADCgEJAQAAAA==.Coopah:BAAALgAECgkJBQAAAA==.Corgibutts:BAAALgAFFAIJAgAAAA==.Corvyr:BAAALgAECgIJAgAAAA==.Cowtee:BAAALgAFFAIJAgAAAA==.',
Cr='Crackjones:BAAALgAECgcJDAAAAA==.Crapsrocks:BAAALgAECgYJCgAAAA==.Crazydave:BAABLgAECn8aAAIXAAkJ7xEoIwDMAQAXAAkJ7xEoIwDMAQAAAA==.Creemywitchu:BAAALgAECgQJBQAAAA==.Crisgmt:BAAALgAECgcJDQAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAABLgAECn8XAAIWAAgJ2RvVGgBCAgAWAAgJ2RvVGgBCAgAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Crul:BAAALgAECgYJBgAAAA==.Cryptìc:BAACLgAFFH8VAAIOAAcJ+hkMBwACAgAOAAcJ+hkMBwACAgAuAAQKfyIAAg4ACQn2IxgDADIDAA4ACQn2IxgDADIDAAEuAAUUBgkXAAMABRkA.Cryptîc:BAACLgAFFH8XAAIDAAYJBRmYNQCTAQADAAYJBRmYNQCTAQAuAAQKfzAAAgMACAnSJcUZAL8CAAMACAnSJcUZAL8CAAAA.Cráckjones:BAAALgAECgEJAQAAAA==.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8YAAIDAAcJjxlOXwAdAgADAAcJjxlOXwAdAgAAAA==.Dabbia:BAACLgAFFH8NAAQIAAYJtRZcDgChAAAJAAQJ1Q8sWAAXAQAIAAMJ/RpcDgChAAAKAAIJnBkBAgBfAAAuAAQKfygABAgACAmoHpgIAN4BAAgABgl/IJgIAN4BAAkABgmPG5JXAMEBAAoABgnlGgkTALMBAAAA.Daedleus:BAAALgAECgQJBQAAAA==.Damented:BAABLgAECn8bAAMIAAgJKRP3DgBtAQAIAAgJKRP3DgBtAQAJAAMJyw994gCXAAAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnchild:BAAALgADCgEJAgABLgAECgYJHwABALMSAA==.Dawnpaw:BAABLgAECn8iAAMWAAkJqhNaIgCgAQAWAAgJcxFaIgCgAQAfAAUJpBUxRADuAAAAAA==.Daymonesus:BAAALgAECgUJBQAAAA==.',
De='Deadvocate:BAAALgADCgMJAwAAAA==.Deathballz:BAACLgAFFH8IAAITAAMJGxEfEQB9AAATAAMJGxEfEQB9AAAuAAQKfzYAAhMACQl8GBE6ABgCABMACQl8GBE6ABgCAAAA.Deathsbreach:BAABLgAECn8ZAAINAAgJpREVZQBdAQANAAgJpREVZQBdAQAAAA==.Deathsmite:BAAALgAECgIJBAAAAA==.Deathtee:BAABLgAECn8YAAITAAgJrxxPRgAiAgATAAgJrxxPRgAiAgABLgAFFAMJAwAFAAAAAA==.Dedbeef:BAAALgAECgYJBgABLgAECggJIwAYAEQNAA==.Deepwaters:BAAALgADCgcJDgAAAA==.Deezhands:BAAALgADCgYJCwAAAA==.Dekuslice:BAABLgAECn8gAAIhAAkJyBSQJQCfAQAhAAkJyBSQJQCfAQAAAA==.Delafant:BAAALgAECgYJCwAAAA==.Deldaris:BAAALgAECgMJBAAAAA==.Delthrus:BAAALgADCgYJBgABLgAECgkJLwAdAPEYAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonarc:BAAALgAECgYJBwAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Deposate:BAAALgAECgEJBAAAAA==.Derpyderp:BAAALgAECgEJAgABLgAFFAMJCAADAJMGAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgAFAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAAALgAECgUJEAAAAA==.Devonate:BAAALgAECgEJAQAAAA==.',
Di='Diatomaceous:BAAALgAECgEJAQAAAA==.Dinkys:BAAALgADCgYJCwABLgAECgYJDwAFAAAAAA==.Dinsum:BAAALgADCgkJJQAAAA==.Diogenist:BAAALgAECgYJCwAAAA==.Dirtydhunter:BAAALgAECgYJBgAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAABLgAFFH8HAAITAAMJyhzifgAJAQATAAMJyhzifgAJAQABLgAFFAMJCgAiABImAA==.',
Dn='Dnaldtrump:BAAALgAECgQJBAAAAA==.',
Do='Dogdad:BAAALgADCgcJCwAAAA==.Doktarboom:BAAALgAECgMJAwAAAA==.Doktardoodad:BAAALgAECgcJDgAAAA==.Doktartides:BAAALgAECgEJAQAAAA==.Doktarzen:BAAALgAECgQJBgAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Donkypunch:BAAALgADCgcJBwAAAA==.Donut:BAAALgAECgUJCAAAAA==.Doomslayer:BAABLgAECn8aAAINAAkJfAn0YgB4AQANAAkJfAn0YgB4AQAAAA==.Doresearch:BAABLgAECn8iAAICAAgJkBU2LwCEAQACAAgJkBU2LwCEAQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAABLgAECn8ZAAIJAAgJSh+AQADbAQAJAAgJSh+AQADbAQAAAA==.Dragontee:BAAALgADCgQJBAAAAA==.Drakarys:BAAALgAECgYJCwAAAA==.Drakex:BAAALgAECgUJBwAAAA==.Drakoswrath:BAAALgAECgUJBgAAAA==.Dreadarcane:BAAALgAECgEJAgAAAA==.Dreamyskull:BAAALgADCgQJAgAAAA==.Drengist:BAABLgAECn8zAAIgAAkJhRrYDgBNAgAgAAkJhRrYDgBNAgAAAA==.Drexybear:BAABLgAECn8vAAMEAAkJOCKjAQD/AgAEAAkJfiGjAQD/AgASAAgJdCF4JABRAgAAAA==.Drezbi:BAABLgAECn8UAAISAAUJhBjwdwBQAQASAAUJhBjwdwBQAQAAAA==.Droodmon:BAAALgAECgQJDAAAAA==.Drpally:BAAALgADCgEJAQAAAA==.Drpebbles:BAAALgAECgQJCwAAAA==.Druidskillz:BAAALgADCgEJAQAAAA==.Druisty:BAAALgAECgEJAQAAAA==.',
Du='Dulcineru:BAAALgAECgEJAQABLgAECgkJJgAOAMcHAA==.Dunbarth:BAABLgAECn8jAAIbAAkJbg1UhQBlAQAbAAkJbg1UhQBlAQAAAA==.Durzaman:BAAALgAECgYJDQAAAA==.Durzuk:BAAALgAECgMJAwAAAA==.Duskhoof:BAAALgADCgIJAwAAAA==.',
Dy='Dynastyy:BAAALgAECgkJBwAAAA==.',
['Dé']='Dévílyñ:BAABLgAECn8qAAIJAAkJVgu0WgCOAQAJAAkJVgu0WgCOAQAAAA==.',
['Dí']='Díscordía:BAAALgAECgEJAQABLgAECgkJSgAXAB8iAA==.',
['Dü']='Dük:BAABLgAECn8YAAMJAAcJjxHgmgAHAQAJAAYJMRLgmgAHAQAKAAIJZA5RTACIAAAAAA==.',
Ed='Eddai:BAAALgAECgEJAQAAAA==.',
Ef='Eff:BAACLgAFFH8IAAIiAAQJtwfOAwDUAAAiAAQJtwfOAwDUAAAuAAQKfxoAAiIACQmSDyMYANkBACIACQmSDyMYANkBAAAA.',
Eg='Eggy:BAAALgAECgkJDgAAAA==.',
Ek='Eks:BAAALgADCgkJKwAAAA==.',
El='Eldraaqeyn:BAAALgAECgMJAwAAAA==.Electrcfrost:BAAALgAECgEJAQAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elishii:BAAALgADCgYJBgAAAA==.Elkanàh:BAAALgAFFAEJAgABLgAFFAMJBQAPAE0MAA==.Ell:BAAALgADCgEJAQAAAA==.Elleynle:BAABLgAECn8VAAIEAAYJExEzFQASAQAEAAYJExEzFQASAQAAAA==.Elunara:BAACLgAFFH8kAAIVAAUJ9hvWCgBFAQAVAAUJ9hvWCgBFAQAuAAQKf2sAAhUACQkmIjkDAPcCABUACQkmIjkDAPcCAAEuAAQKCQkhAAgA1h8A.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.Emptor:BAAALgAECgEJAQAAAA==.Emreezus:BAAALgAFFAMJBAABLgAFFAUJIgAbAO4gAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.Enigmä:BAAALgADCgYJCgAAAA==.Enio:BAAALgAECgMJAwAAAA==.',
Er='Ericuh:BAABLgAECn8fAAMBAAYJsxJ7aAAiAQABAAYJsxJ7aAAiAQACAAEJjAd+ugAiAAAAAA==.',
Es='Escanör:BAAALgAECgYJEAABLgAECgkJIQAGAGQiAA==.Essekk:BAACLgAFFH8ZAAIDAAUJcRyNTABHAQADAAUJcRyNTABHAQAuAAQKfy8AAgMACQklH2AWACMDAAMACQklH2AWACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Event:BAAALgADCgUJBQAAAA==.Evodrak:BAAALgADCgYJBwAAAA==.Evokeeznutz:BAAALgAECgcJCQABLgAFFAQJEAAIAE8cAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.Exploreswag:BAAALgAECgcJDwAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.',
['Eí']='Eír:BAAALgAECgYJCwABLgAECgkJSgAXAB8iAA==.',
Fa='Fairyholy:BAAALgADCgIJAgAAAA==.Faith:BAAALgAECgYJBwAAAA==.Fallenchaos:BAAALgAECgYJBgAAAA==.Famjam:BAABLgAECn8XAAMbAAgJyBMYwAAIAQAbAAYJkxEYwAAIAQAYAAMJKBh+KADTAAAAAA==.Fao:BAAALgAECgQJBQAAAA==.Fastrialimas:BAAALgAECgcJDQAAAA==.Fatigue:BAAALgADCgMJAQAAAA==.Fatpo:BAABLgAECn8kAAMXAAgJzSC6BgDiAgAXAAgJzSC6BgDiAgAOAAUJsCKbJwCRAQABLgAFFAQJFQAWAB8jAA==.Fayjhu:BAABLgAECn8mAAIDAAgJaAtRkQBVAQADAAgJaAtRkQBVAQAAAA==.',
Fe='Felwingz:BAAALgAECgEJAQAAAA==.Ferbos:BAAALgAECgIJAwAAAA==.Feylock:BAABLgAECn8UAAIJAAcJ7RDMmgAIAQAJAAcJ7RDMmgAIAQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgAECgYJDAAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAACLgAFFH8YAAIiAAUJBx9eEwByAQAiAAUJBx9eEwByAQAuAAQKfzIAAiIACQk9HtULAGcCACIACQk9HtULAGcCAAAA.',
Fr='Frigate:BAABLgAECn8YAAIDAAcJWgUS2QA/AQADAAcJWgUS2QA/AQAAAA==.Frihgate:BAABLgAECn8aAAISAAgJNhZ2MgDmAQASAAgJNhZ2MgDmAQAAAA==.Frostbiteme:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frosteenie:BAAALgAECgEJAQAAAA==.Frostiebyte:BAAALgAECgkJAQAAAA==.Frostmyface:BAAALgAFFAIJAwAAAA==.Frozenbeard:BAAALgAECgcJEwAAAA==.',
Fu='Fugarra:BAAALgAECgYJDwABLgAFFAIJBQASAOAFAA==.Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAACLgAFFH8GAAIgAAMJSR4cJQAVAQAgAAMJSR4cJQAVAQAuAAQKfxYAAiAACAl/IZkQADcCACAACAl/IZkQADcCAAAA.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgAECgcJCAAAAA==.Fuzi:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.Fuzybritches:BAAALgAECgQJBQABLgAECgcJCQAFAAAAAA==.',
Fy='Fyafya:BAAALgAFFAEJAQABLgAFFAgJHQAjAFobAA==.Fyah:BAACLgAFFH8FAAIbAAMJsxjXZgDhAAAbAAMJsxjXZgDhAAAuAAQKfxsAAhsACQmZIKIxADoCABsACQmZIKIxADoCAAEuAAUUCAkdACMAWhsA.Fyaza:BAAALgAECgcJCwABLgAFFAgJHQAjAFobAA==.',
Ga='Gaga:BAAALgAECgEJAQAAAA==.Gariantel:BAAALgAECgMJDAAAAA==.Garleck:BAAALgAECgYJCwAAAA==.Garou:BAABLgAECn8zAAILAAgJSyGLDAChAgALAAgJSyGLDAChAgAAAA==.Gaygar:BAAALgADCgcJEwAAAA==.',
Ge='Geekylock:BAAALgAECgcJEwABLgAECggJIwAYAEQNAA==.Geekymage:BAAALgAECgYJEwABLgAECggJIwAYAEQNAA==.Geekyxgenome:BAAALgAECgYJCwABLgAECggJIwAYAEQNAA==.Genesis:BAABLgAFFH8LAAITAAMJrR3DegAPAQATAAMJrR3DegAPAQAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgYJEwAAAA==.Gerttie:BAAALgAECgUJCQAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gigabytch:BAAALgAFFAEJAQAAAA==.Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAgJLgAMANkfAA==.Gistlek:BAAALgAECggJBAAAAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAABLgAECn8cAAIIAAkJWgxIAACxAQAIAAkJWgxIAACxAQAAAA==.Gorehammer:BAABLgAECn8qAAITAAgJlxmHUAAAAgATAAgJlxmHUAAAAgAAAA==.Gorto:BAAALgAECgEJAQAAAA==.',
Gr='Grassmoker:BAAALgAECgEJBAAAAA==.Gravediger:BAAALgAECgcJEQAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Grek:BAACLgAFFH8NAAMdAAQJ6iKxCwBzAQAdAAQJ6iKxCwBzAQAcAAMJvQSmLwCjAAAuAAQKfxYAAx0ABwn1HVYPAPMBAB0ABgkHI1YPAPMBABwAAQmfBFuJAB4AAAAA.Gridxx:BAABLgAECn8WAAMhAAcJDhOZLwBhAQAhAAcJDhOZLwBhAQAeAAEJkARiYgAfAAAAAA==.Grief:BAAALgADCgEJAQAAAA==.Grievex:BAABLgAECn9TAAIbAAkJgQ2YAQCTAQAbAAkJgQ2YAQCTAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.Grimblefritz:BAAALgADCgMJAwAAAA==.Gronthar:BAAALgAECgEJAQAAAA==.',
['Gî']='Gîgâbussy:BAAALgAECgYJBgAAAA==.',
Ha='Haikuu:BAAALgAECgUJCwAAAA==.Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgMJBAAAAA==.Hanyu:BAABLgAECn8UAAITAAkJ0xLQQwD3AQATAAkJ0xLQQwD3AQAAAA==.Haranar:BAAALgAECgEJAwAAAA==.Harkelem:BAAALgAECgkJAQAAAA==.Haydayy:BAAALgADCgYJBgAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healabae:BAAALgAECgkJCQABLgAECgEJAQAFAAAAAA==.Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAABLgAECn8hAAMXAAgJ6hYKGAAOAgAXAAgJ6hYKGAAOAgAMAAIJ4wMccwBCAAAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Hemobloom:BAAALgAECgIJAgABLgAFFAUJIgAbAO4gAA==.Hemolock:BAACLgAFFH8LAAIJAAQJbw4bWQAVAQAJAAQJbw4bWQAVAQAuAAQKfyIAAwkABglpG/BXAJUBAAkABglpG/BXAJUBAAoAAQkAAItXAAAAAAEuAAUUBQkiABsA7iAA.Hemostasis:BAACLgAFFH8iAAIbAAUJ7iC8KgBiAQAbAAUJ7iC8KgBiAQAuAAQKfysABBsACQnwIM0eAI0CABsACQnwIM0eAI0CACQABAm8CZdqAIwAABgAAQksDpJSACsAAAAA.Herjä:BAABLgAECn9KAAQXAAkJHyJ9BAA6AwAXAAkJHyJ9BAA6AwAMAAYJrRNgJQBpAQAOAAEJJgrfjgAsAAAAAA==.Hexmora:BAAALgAECgEJAgAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.Hirok:BAAALgADCgYJBgAAAA==.',
Ho='Homeslice:BAAALgAECggJEQAAAA==.Hoocha:BAAALgADCgYJBgABLgAFFAQJEAAIAE8cAA==.Hoollymollyy:BAAALgAECgEJAQAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.Hotandcold:BAAALgAECgEJAgAAAA==.',
Hu='Hunterskillz:BAAALgAECgUJBQAAAA==.Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgYJBwAAAA==.Huun:BAACLgAFFH8JAAIjAAMJ9h0fGQAJAQAjAAMJ9h0fGQAJAQAuAAQKfzoAAiMACQmIH70EAOACACMACQmIH70EAOACAAAA.',
Hy='Hyasynthia:BAAALgAECgkJDgAAAA==.Hycindraeda:BAAALgAECgYJBwAAAA==.',
['Hú']='Húckleberry:BAAALgAECggJEAAAAA==.',
Ia='Iamgabrielsj:BAAALgAECgEJAQAAAA==.Iamnsfw:BAAALgAECgcJEgAAAA==.',
Ic='Icelcelance:BAABLgAFFH8SAAIDAAYJehr5MACnAQADAAYJehr5MACnAQAAAA==.',
Ii='Iionel:BAAALgAECgEJAgAAAA==.',
Il='Illestone:BAAALgAECgMJAwABLgAFFAIJCAAYABcOAA==.Illuminee:BAAALgAECgIJAgABLgAECgIJAgAFAAAAAA==.Illydan:BAABLgAECn8iAAMNAAkJFxuRGACCAgANAAkJFxuRGACCAgAZAAEJGAgTegAmAAAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn83AAIDAAkJPSAfFADhAgADAAkJPSAfFADhAgAAAA==.Impedup:BAAALgAECgUJBQAAAA==.',
In='Indigø:BAAALgAECgUJDgAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAFFAMJBAAFAAAAAA==.',
Ir='Irezufortips:BAAALgAECgcJCwABLgAFFAIJBQASAOAFAA==.Ironhide:BAAALgAECgQJBAAAAA==.Ironshadow:BAAALgADCgEJAQAAAA==.Irrenadro:BAABLgAECn8XAAIbAAgJTQ6+fQB+AQAbAAgJTQ6+fQB+AQAAAA==.Irvainee:BAAALgAECgYJDAABLgAECgcJEQAFAAAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Iy='Iyahna:BAAALgAECgEJAgAAAA==.',
Ja='Jaarhai:BAAALgADCgEJAQAAAA==.Jadechaos:BAAALgAECgEJAQAAAA==.Jadireux:BAAALgAECgYJEgAAAA==.Jaelia:BAAALgADCgEJAQAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jandina:BAAALgAECgMJAwAAAA==.Jarnabas:BAAALgAECggJCgAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jiffypop:BAAALgADCgUJBQAAAA==.Jimboslice:BAAALgADCgcJBwAAAA==.Jimmyhoofa:BAAALgADCgkJDQAAAA==.Jingleparts:BAAALgAECgUJCwABLgAECgkJHwAXAIocAA==.',
Jo='Joes:BAABLgAECn8mAAMSAAcJ9hdwYQCEAQASAAcJ9hdwYQCEAQAEAAYJdQfzHwCwAAAAAA==.Jonesy:BAAALgAECgUJDAAAAA==.Jophiel:BAAALgADCgkJCwAAAA==.Jorath:BAAALgAECgUJBgABLgAFFAIJBQASAOAFAA==.Jorkota:BAAALgADCgEJAQAAAA==.',
Ju='Juicygossip:BAAALgAECgYJBwAAAA==.Jujupowa:BAABLgAECn8kAAIbAAgJZwclrgAiAQAbAAgJZwclrgAiAQAAAA==.Junebug:BAAALgAECgQJBQAAAA==.Justicus:BAAALgADCgMJAwAAAA==.',
['Jë']='Jëssë:BAAALgAECgQJBAAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kaelthalar:BAAALgADCgEJAQABLgAFFAMJCQAbAMIgAA==.Kagal:BAABLgAECn8WAAIjAAgJ3RExDwDSAQAjAAgJ3RExDwDSAQAAAA==.Kaidan:BAABLgAECn8pAAISAAkJpBJCTQC6AQASAAkJpBJCTQC6AQAAAA==.Kaipriest:BAAALgAECgQJBAAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kaledra:BAAALgAECgQJBgAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgQJBQAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAFFAQJDAAZAMQhAA==.Katanya:BAAALgAECgYJCwABLgAECgkJIQAIANYfAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8cAAISAAYJrxb5GAClAQASAAYJrxb5GAClAQAAAA==.Keftheals:BAAALgAECgkJCgAAAA==.Keiriline:BAABLgAECn82AAQlAAkJGhlHCgDaAQAlAAkJCxlHCgDaAQAmAAUJlhFsMADfAAATAAEJYwCzqAEUAAAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAABLgAECn8kAAIjAAkJxhvRDgA+AgAjAAkJxhvRDgA+AgAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgYJCgAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.Khalysea:BAAALgADCgIJAgABLgAECgkJIQAIANYfAA==.',
Ki='Kiimari:BAAALgAECggJDAAAAA==.Killbreed:BAACLgAFFH8MAAIeAAQJlh6MBABzAQAeAAQJlh6MBABzAQAuAAQKfygAAh4ACAmcI10EALsCAB4ACAmcI10EALsCAAAA.Kinkster:BAAALgAECggJCgAAAA==.Kirinani:BAAALgAECgEJAQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knight:BAAALgAECgYJDAABLgAFFAUJEAAfABciAA==.Knugg:BAAALgAECgMJAwAAAA==.Knuggz:BAABLgAECn8rAAILAAkJbCC7CQDHAgALAAkJbCC7CQDHAgAAAA==.',
Ko='Kolduna:BAAALgADCgUJBQAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgADCgkJEQAAAA==.',
Kr='Krestaul:BAAALgAECgcJEAAAAA==.',
Ku='Kurthalan:BAAALgAECgQJDAAAAA==.Kuumaneko:BAACLgAFFH8NAAIJAAQJhCCfMACDAQAJAAQJhCCfMACDAQAuAAQKfzYAAwkACQlbISoKAP8CAAkACQlbISoKAP8CAAoABgmvBwwxAPUAAAAA.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJEgAAAA==.Kyledh:BAACLgAFFH8VAAINAAQJyx/4AwBJAQANAAQJyx/4AwBJAQAuAAQKfzwAAw0ACQkjJtEBAG0DAA0ACQkjJtEBAG0DABoAAQluIf8jAGIAAAAA.Kyletotems:BAABLgAFFH8RAAMHAAUJGSURAwCqAQAHAAQJGSURAwCqAQABAAQJsCKhAgAwAQAAAA==.Kyllgorre:BAAALgAECgEJAQAAAA==.Kynyine:BAAALgADCgcJCAAAAA==.',
La='Lancee:BAAALgAECgcJCgAAAA==.Landridan:BAAALgAECgMJBQAAAA==.Lanstoll:BAAALgAECgkJDQAAAA==.Lanthin:BAAALgADCggJEgAAAA==.Larzoe:BAAALgAECgYJCQABLgAECgkJIgAZAOojAA==.Larzoh:BAABLgAECn8iAAMZAAkJ6iOkAwBGAwAZAAkJ6iOkAwBGAwANAAMJSw4q8QBdAAAAAA==.Laudrup:BAAALgAECgEJAQAAAA==.Lawdhots:BAAALgAECgMJBAAAAA==.Laylaria:BAAALgADCgEJAQAAAA==.',
Le='Leanwushin:BAABLgAECn8VAAIBAAYJcA2gBACHAAABAAYJcA2gBACHAAAAAA==.Lee:BAAALgADCgYJBQABLgAFFAMJCgATAD0hAA==.Legadiaus:BAAALgAECggJCgAAAA==.Lemonheads:BAABLgAECn9NAAMMAAkJ8yC5AwBkAwAMAAkJ8yC5AwBkAwAOAAEJ4QEtagAjAAAAAA==.Lenardo:BAAALgADCgcJBwAAAA==.Lethargy:BAAALgAECgYJBgAAAA==.',
Li='Liaenara:BAAALgAECgEJAQAAAA==.Lidorila:BAAALgAECgMJAwAAAA==.Lightbranger:BAAALgAECgUJBAAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgcJCgABLgAECgYJFAALAPkJAA==.Lilplottwist:BAAALgAECgIJAgAAAA==.Lilwiz:BAABLgAECn8VAAIKAAUJBRXrFQD5AAAKAAUJBRXrFQD5AAAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Linnxd:BAAALgAECgIJAwABLgAECgMJBgAFAAAAAA==.Linnxs:BAAALgAECgIJBAABLgAECgMJBgAFAAAAAA==.Linnxvx:BAAALgAECgMJBgAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgMJBQAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgAFAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lokibalboa:BAAALgAECgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwAFAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgAFAAAAAA==.Loxley:BAAALgAECgYJDAAAAA==.',
Ls='Lshaman:BAABLgAFFH8FAAIBAAMJ7Bv1QQDeAAABAAMJ7Bv1QQDeAAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAABLgAECn8dAAIOAAgJnxTpIQC4AQAOAAgJnxTpIQC4AQAAAA==.Lunahunter:BAAALgAECgEJAQAAAA==.Lunarcricket:BAAALgAECgUJCAABLgAFFAMJCQAYAKogAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwAFAAAAAA==.',
Ly='Lyncha:BAAALgAECgcJCQABLgAFFAMJCQAYAKogAA==.Lynchà:BAACLgAFFH8JAAIYAAMJqiBcBgAaAQAYAAMJqiBcBgAaAQAuAAQKfzcAAhgACQlLJGABAD0DABgACQlLJGABAD0DAAAA.Lynchá:BAAALgADCgIJAgAAAA==.Lynchä:BAAALgADCgEJAQABLgAFFAMJCQAYAKogAA==.',
Ma='Maakun:BAABLgAECn8dAAQXAAcJ3gxoOwBNAQAXAAcJ2gdoOwBNAQAOAAUJ8wcWQAD2AAAMAAQJHg2rOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJDgABLgAECgUJBgAFAAAAAA==.Madette:BAAALgADCggJCAABLgAFFAgJLgAMANkfAA==.Mageapoug:BAAALgADCgcJBwABLgAFFAQJEAAZAHcZAA==.Magia:BAAALgAECgcJCwAAAA==.Magmalance:BAAALgAFFAEJAQABLgAECggJGQANAKURAA==.Mahoragga:BAAALgADCgYJBgAAAA==.Mahzad:BAACLgAFFH8OAAIBAAUJgyFBEwDMAQABAAUJgyFBEwDMAQAuAAQKfyYAAwEABwljIzoYAFQCAAEABwljIzoYAFQCAAIABgmmDddWAOAAAAAA.Makaveli:BAAALgADCgYJBgAAAA==.Maladi:BAAALgADCgkJJAAAAA==.Malfrun:BAABLgAECn8vAAMdAAkJ8RhDCwA5AgAdAAkJ8RhDCwA5AgALAAMJdQZ3fgB8AAAAAA==.Manaena:BAAALgADCgQJAwAAAA==.Marinnite:BAAALgADCgYJDgAAAA==.Markzugrberg:BAAALgADCgkJCQAAAA==.Marox:BAACLgAFFH8IAAIDAAQJwgrPbgAFAQADAAQJwgrPbgAFAQAuAAQKfxgAAgMACQldHXZDAG4CAAMACQldHXZDAG4CAAAA.Marrøwgar:BAAALgAECgcJEQABLgAECggJGQANAKURAA==.Marshmellows:BAAALgAECgYJBgABLgAECgYJHwABALMSAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAACLgAFFH8dAAIJAAYJHiXEGAD9AQAJAAYJHiXEGAD9AQAuAAQKfyMAAwkACQmGJEoVANUCAAkACAmGJEoVANUCAAoAAQkAANtVAG0AAAAA.Matooka:BAABLgAECn8tAAISAAkJXg1VTQC6AQASAAkJXg1VTQC6AQAAAA==.Maynji:BAAALgAECgMJAwAAAA==.Mayushi:BAAALgAECgYJCQAAAA==.',
Mc='Mcthugger:BAAALgAECgEJAQABLgAFFAIJCAAYABcOAA==.',
Me='Mebforu:BAAALgADCgEJAQAAAA==.Meencurry:BAABLgAECn8kAAIDAAgJghXYZgCvAQADAAgJghXYZgCvAQAAAA==.Megozugzug:BAAALgAFFAMJBAAAAA==.Meyneth:BAAALgAECgQJCAAAAA==.',
Mi='Mikaì:BAAALgAECgkJEgAAAA==.Mikehawkener:BAAALgAECgYJDwAAAA==.Mirlone:BAAALgAECgYJCQAAAA==.Misleading:BAABLgAECn8XAAIdAAUJNhgzJQAIAQAdAAUJNhgzJQAIAQAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Missdead:BAAALgAECgEJAQAAAA==.Mistfisting:BAACLgAFFH8HAAIWAAMJ8xVzOgC8AAAWAAMJ8xVzOgC8AAAuAAQKfxQAAhYABwmEHjIkAP8BABYABwmEHjIkAP8BAAAA.',
Mo='Moderato:BAAALgAECgkJDgAAAA==.Moelleri:BAABLgAECn8dAAITAAgJaBlAWQC6AQATAAgJaBlAWQC6AQAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgUJBgAFAAAAAA==.Molodeath:BAAALgAECgYJDQAAAA==.Mommÿ:BAACLgAFFH8OAAIMAAUJ0QvWIQBBAQAMAAUJ0QvWIQBBAQAuAAQKfyEAAwwACQkIFwgSAFYCAAwACQkIFwgSAFYCAA4AAQl0ABZtAAcAAAAA.Moneymage:BAAALgAECgcJCwAAAA==.Monkgroom:BAACLgAFFH8aAAIWAAUJGBCVKQAjAQAWAAUJGBCVKQAjAQAuAAQKfx0AAxYACQmaFA8XAAkCABYACQmaFA8XAAkCAB8ABgnyCto5ADYBAAAA.Monsignor:BAAALgAECgIJCwAAAA==.Montra:BAACLgAFFH8HAAIVAAMJ6g6jHgCkAAAVAAMJ6g6jHgCkAAAuAAQKfzMAAxUACQn6HHkGAJYCABUACQn6HHkGAJYCAB4ABQkCCf4eAOsAAAAA.Mooharahgha:BAAALgAECgEJAQAAAA==.Mordach:BAAALgAECgEJAgAAAA==.Moreilira:BAAALgAECgYJEQAAAA==.Mornshield:BAABLgAECn8jAAMbAAYJWxSmkQBZAQAbAAYJIxCmkQBZAQAYAAUJUxMIJgDZAAABLgAFFAIJBQASAOAFAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motorinkashi:BAACLgAFFH8HAAIPAAMJfwqESQCUAAAPAAMJfwqESQCUAAAuAAQKfxoAAw8ACQnmHrQIAC0DAA8ACQnmHrQIAC0DABUAAwkXD61NAHUAAAAA.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAABLgAECn8aAAIdAAgJoRTaGwBYAQAdAAgJoRTaGwBYAQAAAA==.Muddthir:BAAALgAECgQJBAABLgAECggJGgAdAKEUAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCwAAAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwAbANocAA==.',
Na='Nahaine:BAAALgADCggJCAAAAA==.Naronar:BAAALgAECgEJAgAAAA==.Nazrra:BAABLgAECn8bAAIdAAkJIxRkEAACAgAdAAkJIxRkEAACAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgAECgEJAQAAAA==.Nelorim:BAAALgAECgIJAgAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Nenad:BAAALgADCgEJAQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nerodic:BAAALgADCgYJBgABLgAFFAQJEwATAMgYAA==.Nestaah:BAAALgAFFAIJBAAAAA==.Nettra:BAAALgAECgIJCgAAAA==.Newtnewt:BAAALgAECgUJBgAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nicneven:BAAALgADCgkJCQAAAA==.Nininbrew:BAAALgAECgEJAwABLgAECgcJGwAMAGUTAA==.Nirath:BAABLgAECn88AAIDAAkJEhZbOQAzAgADAAkJEhZbOQAzAgAAAA==.',
No='Nobainer:BAAALgAECgMJAwAAAA==.Noed:BAAALgAECgMJBgAAAA==.Nohkana:BAAALgAECgEJAQAAAA==.Nohkano:BAACLgAFFH8KAAIgAAMJPSQUHgA6AQAgAAMJPSQUHgA6AQAuAAQKfzsAAiAACQn8JecAAGsDACAACQn8JecAAGsDAAAA.Nokinkshame:BAAALgADCggJCQABLgAECgkJHwAXAIocAA==.Nokt:BAAALgADCgQJBAAAAA==.Noobymonk:BAAALgAECggJEwAAAA==.Noralise:BAAALgAECgYJEwAAAA==.Northerndk:BAABLgAECn8WAAITAAcJKgW76QDIAAATAAcJKgW76QDIAAAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgQJCAAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.Nutthunter:BAAALgAECgEJAwAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAIDAAgJVhTDbAD8AQADAAgJVhTDbAD8AQAAAA==.',
Oa='Oakmain:BAAALgAECgUJBQAAAA==.',
Oc='Octavarium:BAABLgAECn8hAAIWAAgJExzBFgBjAgAWAAgJExzBFgBjAgAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.Odinspriest:BAAALgADCgcJBwAAAA==.Odinsvulpera:BAAALgADCgYJBwAAAA==.',
Oe='Oennomaus:BAAALgAECgUJBgAAAA==.',
Of='Offspec:BAAALgAECgEJAgAAAA==.',
Oh='Ohyshii:BAAALgAECgMJBQAAAA==.',
Ol='Oldglory:BAAALgAECgcJBwAAAA==.Olorinziln:BAAALgAECgYJBgAAAA==.',
On='Oneshothel:BAABLgAECn8ZAAISAAcJ5xhETQC6AQASAAcJ5xhETQC6AQAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwAbANocAA==.',
Or='Orcpeon:BAABLgAECn8UAAISAAYJYg01lQAVAQASAAYJYg01lQAVAQABLgAECgkJRwAbABYhAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAABLgAECn8WAAMcAAYJmRYpEwByAQAcAAYJDxUpEwByAQALAAQJyRHGawAHAQABLgAECgkJHwAXAIocAA==.Overdoze:BAAALgAECgEJAQAAAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Paichan:BAAALgAECgEJAQAAAA==.Palakazam:BAAALgAECgEJAQAAAA==.Palaweenie:BAAALgAECgEJAQAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgAECgQJCAAAAA==.Pancaked:BAAALgAECggJEwABLgAECgkJHwAXAIocAA==.Pangpang:BAAALgADCgIJAgAAAA==.Pantheons:BAAALgADCgIJAwAAAA==.Paradon:BAAALgADCgEJAQAAAA==.Paradox:BAAALgAECgQJBAABLgAFFAYJGwAeAAchAA==.Parsi:BAACLgAFFH8LAAIaAAMJDRfSCADGAAAaAAMJDRfSCADGAAAuAAQKfx0AAhoACQlKIFcCAN4CABoACQlKIFcCAN4CAAAA.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Pennywhys:BAAALgAECgEJAQAAAA==.Penut:BAAALgAECgEJAgAAAA==.Perritax:BAABLgAECn8iAAIDAAcJdhHZjgBaAQADAAcJdhHZjgBaAQAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwABLgAECgQJBQAFAAAAAA==.Phialrog:BAAALgAECgYJCgAAAA==.Phoebelyria:BAAALgAECgYJEwAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgAFAAAAAA==.',
Pi='Pickelz:BAAALgADCgMJAwAAAA==.Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgYJDAAAAA==.Pingdoo:BAAALgAECgIJAwAAAA==.Pingdu:BAAALgAECgEJAgAAAA==.Pingdui:BAAALgAECgEJAgAAAA==.Pingryun:BAAALgAECgEJAgAAAA==.Piptip:BAAALgADCgcJBwAAAA==.Pizzaparty:BAAALgAECgQJAwABLgAECgkJHwAXAIocAA==.',
Pl='Pletenko:BAAALgAECgEJAQAAAA==.',
Po='Pofat:BAACLgAFFH8VAAIWAAQJHyNqHACPAQAWAAQJHyNqHACPAQAuAAQKfxQAAxYACAkgHNoSAIYCABYACAkgHNoSAIYCAB8AAgnWEZl1AGUAAAAA.Polis:BAABLgAECn9HAAMbAAkJFiG+DgDwAgAbAAkJFiG+DgDwAgAYAAcJGROMGABYAQAAAA==.Pomol:BAABLgAECn8VAAISAAcJDRf1SACPAQASAAcJDRf1SACPAQAAAA==.Pomoly:BAAALgAECgIJBAAAAA==.Poppafury:BAABLgAECn8ZAAIdAAcJJBWnGwBaAQAdAAcJJBWnGwBaAQAAAA==.Potent:BAABLgAECn8gAAMTAAgJ4RFMhQBZAQATAAgJ4RFMhQBZAQAmAAQJbQaPOgBvAAAAAA==.Poubear:BAAALgAECgYJCAABLgAFFAIJBQASAOAFAA==.Pougadina:BAAALgAECgYJCAABLgAFFAQJFQAWAB8jAA==.',
Pr='Primal:BAAALgADCgIJAgAAAA==.Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAACLgAFFH8IAAITAAMJ1giitQC8AAATAAMJ1giitQC8AAAuAAQKfxgAAxMACAn1FqhdAK8BABMACAn1FqhdAK8BACYAAQlLBH5PABcAAAAA.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAABLgAECn8YAAIDAAcJMwayzgD0AAADAAcJMwayzgD0AAABLgAFFAIJBQASAOAFAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Qi='Qizzle:BAAALgADCgMJAwAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAIbAAYJYxbTigBlAQAbAAYJYxbTigBlAQAAAA==.Ramshunter:BAABLgAECn8fAAMSAAkJFiFcBwAaAwASAAkJFiFcBwAaAwAEAAIJ4xF3OAA9AAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgAECgUJCgAAAA==.Ratnob:BAABLgAECn8xAAITAAkJhhv1KgBUAgATAAkJhhv1KgBUAgAAAA==.Ravnaar:BAAALgAECgkJDwAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.Razzledazzl:BAAALgAECgUJBQAAAA==.',
Re='Reddemon:BAAALgAECgEJAQABLgAFFAQJDQAdAOoiAA==.Redstraw:BAAALgADCgYJBwAAAA==.Relda:BAAALgAFFAIJBAAAAA==.Remye:BAAALgAECgkJCgAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Rennshi:BAACLgAFFH8MAAIZAAQJxCE/AQARAQAZAAQJxCE/AQARAQAuAAQKfyEAAhkACQlBJAgEADsDABkACQlBJAgEADsDAAAA.Retpally:BAABLgAFFH8QAAIdAAcJ7hRtCACwAQAdAAcJ7hRtCACwAQAAAA==.Reyikrat:BAAALgAECgQJCAAAAA==.Rezmee:BAACLgAFFH8IAAITAAMJJSWefQALAQATAAMJJSWefQALAQAuAAQKfxgAAhMACQmIIxEVAMkCABMACQmIIxEVAMkCAAAA.',
Rh='Rheaf:BAAALgAECgYJCQAAAA==.',
Ri='Riarina:BAAALgADCgQJBAAAAA==.Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8WAAIDAAcJPxGIvgBmAQADAAcJPxGIvgBmAQAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rolexiós:BAAALgADCgcJBwAAAA==.Rosario:BAACLgAFFH8eAAQjAAUJ/yD4CgBvAQAjAAUJ/yD4CgBvAQAEAAIJOQ1KHwCZAAASAAEJkxkJnABXAAAuAAQKf08ABCMACQnvIx4CADEDACMACQm5Ih4CADEDAAQACAmhIakNANgCABIABAmrJORQALABAAAA.Royfan:BAAALgAECgQJBAAAAA==.',
Ry='Ryotwar:BAAALgAECgEJAgAAAA==.Rythmatic:BAACLgAFFH8KAAIiAAMJEiY2HAA6AQAiAAMJEiY2HAA6AQAuAAQKfysAAyIACQm/JToCADwDACIACQm/JToCADwDACcABgkNHgMJALUBAAAA.Ryvenox:BAAALgADCgcJBwAAAA==.',
['Ré']='Rénae:BAAALgAECgkJAgABLgAECgkJCAAFAAAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Sakieri:BAABLgAECn9bAAIOAAkJBCMkAADUAgAOAAkJBCMkAADUAgAAAA==.Salhasheals:BAAALgADCgMJAwAAAA==.Salinomycin:BAABLgAECn8UAAIPAAYJ5wffeADMAAAPAAYJ5wffeADMAAAAAA==.Saltyaf:BAAALgADCgMJAwAAAA==.Saltymcnalty:BAAALgAECgEJAQAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sanathas:BAAALgAECgUJBwAAAA==.Sandolorian:BAAALgAECggJDgAAAA==.Sandordel:BAAALgADCgYJDQAAAA==.Sangan:BAABLgAECn8oAAIDAAgJ+yJ0FwDMAgADAAgJ+yJ0FwDMAgAAAA==.Sanguini:BAACLgAFFH8HAAIDAAMJ0Qp9iwDCAAADAAMJ0Qp9iwDCAAAuAAQKfyoAAgMACQk4GHk8ACgCAAMACQk4GHk8ACgCAAAA.Sathari:BAAALgAECgQJCAAAAA==.',
Sc='Schmelzen:BAACLgAFFH8LAAIDAAUJURcvVwAvAQADAAUJURcvVwAvAQAuAAQKfxUAAgMACQkzIr4LABsDAAMACQkzIr4LABsDAAAA.Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAFFAEJAQABLgAFFAMJBAAFAAAAAA==.Sebaz:BAAALgAECgMJBQAAAA==.Selaris:BAAALgAECgcJEgAAAA==.Selathviala:BAAALgADCgMJBQAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8hAAMRAAkJKh7JAQCDAQARAAQJmhvJAQCDAQAQAAgJbBwjAgBxAQAuAAQKfywAAxEACQnJIsEBAC8DABEACAlJI8EBAC8DABAACAlUIygKALYCAAAA.Sergregorsly:BAAALgAECggJCwAAAA==.Serintalis:BAAALgADCgYJBgAAAA==.',
Sh='Shadowblitzx:BAAALgAECgUJEAAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAFFAUJGAAiAAcfAA==.Shangan:BAAALgAECgEJAgAAAA==.Shapestalker:BAAALgADCgcJCgAAAA==.Sharana:BAAALgAECgQJCAAAAA==.Shazzie:BAAALgAECgQJBgAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgAECgMJBwAAAA==.Shirrazaha:BAAALgADCgcJBwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgABLgAFFAQJEgAUANkhAA==.',
Si='Silaris:BAAALgADCgMJBgAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Sinnur:BAAALgAECgQJCQAAAA==.Sinsear:BAAALgAECgUJBgAAAA==.',
Sk='Skeezer:BAABLgAFFH8QAAIIAAQJTxz6AgBvAQAIAAQJTxz6AgBvAQAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizz:BAAALgADCgYJBgAAAA==.Slizzie:BAAALgAECgYJDQAAAA==.Slizziore:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Slizzle:BAAALgAECgEJAgAAAA==.Slizzley:BAAALgAECgEJAgAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.Slycendyce:BAAALgAECgMJAwAAAA==.',
Sm='Smackdiver:BAAALgADCgYJAwAAAA==.Smarfus:BAAALgAECgYJCgABLgAFFAQJDQAdAOoiAA==.Smegspreader:BAAALgAECgEJBAAAAA==.Smilingp:BAAALgADCgkJDwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAABLgAECn8UAAIfAAYJdwM2aQCCAAAfAAYJdwM2aQCCAAAAAA==.Snarge:BAACLgAFFH8UAAIHAAcJBRP8AgCtAQAHAAcJBRP8AgCtAQAuAAQKfxkABAcACQkpGSAKADACAAcACQkpGSAKADACAAEABQlqCMqQALcAAAIAAQkjEsaDADsAAAAA.Sneaktee:BAAALgAFFAEJAQABLgAFFAMJAwAFAAAAAA==.Snuggled:BAAALgAECgUJBQABLgAECgkJHwAXAIocAA==.',
So='Soone:BAAALgAECgkJAQAAAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Sparkydrac:BAAALgAECgYJBgABLgAECggJGQANAKURAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spness:BAAALgAECgUJBQAAAA==.Spunky:BAAALgAECgQJBwAAAA==.',
Sq='Sqquish:BAAALgAECgIJBQAAAA==.Squeaksune:BAAALgADCgcJCAAAAA==.Squiish:BAABLgAECn8hAAIDAAcJ6BFdhQBsAQADAAcJ6BFdhQBsAQAAAA==.',
Sr='Srorcalot:BAABLgAECn8XAAITAAkJWg3uXACxAQATAAkJWg3uXACxAQABLgAFFAIJBQASAOAFAA==.',
St='Steppedon:BAABLgAECn8gAAILAAcJLBK/OQBfAQALAAcJLBK/OQBfAQAAAA==.Steviewonder:BAAALgAECgQJBwAAAA==.Stingerai:BAACLgAFFH8FAAISAAMJnxBaCQCyAAASAAMJnxBaCQCyAAAuAAQKfx0AAhIACQmRIFMoAD0CABIACQmRIFMoAD0CAAEuAAUUAwkKABUAhR8A.Stingeret:BAAALgADCgMJAwABLgAFFAMJCgAVAIUfAA==.Stingerge:BAAALgAECgMJBAABLgAFFAMJCgAVAIUfAA==.Stormweaverr:BAAALgAFFAEJAQABLgAFFAQJDQAdAOoiAA==.',
Su='Sugurugeto:BAAALgADCgEJAQAAAA==.Sunbeamer:BAAALgAECgUJDQAAAA==.Sunnis:BAAALgAECgEJAQAAAA==.Sureman:BAAALgAECgMJBQAAAA==.Suun:BAAALgAECgYJDgAAAA==.',
Sw='Swaggie:BAAALgADCgQJBgAAAA==.Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylentsniper:BAABLgAFFH8FAAMSAAIJ4AUnlwBmAAASAAIJ4AUnlwBmAAAEAAEJmwARPQAoAAAAAA==.Sylvesters:BAAALgADCgcJBwABLgAECgUJBgAFAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
['Sá']='Sága:BAAALgAECgEJAQAAAA==.',
Ta='Tacosalad:BAAALgAECgcJCwABLgAECgkJHwAXAIocAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Talinas:BAAALgADCgYJBgAAAA==.Tamb:BAABLgAECn8gAAIPAAYJwRRyUgBFAQAPAAYJwRRyUgBFAQAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tankndspank:BAAALgADCgYJBgAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Tark:BAAALgADCgYJBwAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwAFAAAAAA==.Tauntisoff:BAAALgADCgMJAwAAAA==.',
Tc='Tchittykitty:BAAALgAECgMJAwAAAA==.',
Te='Tecomonk:BAAALgADCgIJAgAAAA==.Tedious:BAAALgAECgYJEwAAAA==.Teehuntee:BAAALgAFFAMJAwAAAA==.Teepal:BAAALgAECgcJCwABLgAFFAMJAwAFAAAAAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAABLgAECn8qAAIHAAkJox3GBwBNAgAHAAkJox3GBwBNAgAAAA==.Teribullduce:BAACLgAFFH8ZAAIjAAUJehieBwCVAQAjAAUJehieBwCVAQAuAAQKf3oAAiMACQl6IPICABEDACMACQl6IPICABEDAAAA.Terscheckii:BAAALgAFFAIJBAAAAA==.',
Th='Thelian:BAAALgADCgMJAwABLgAECgcJGQASAOcYAA==.Theslimer:BAABLgAECn8aAAMSAAkJShoDJwBEAgASAAkJShoDJwBEAgAEAAYJpQqSVQDzAAAAAA==.Thesukuna:BAAALgAECgUJBwAAAA==.Thingol:BAAALgADCgkJJwAAAA==.Thormor:BAACLgAFFH8uAAIMAAgJ2R+oAQAhAgAMAAgJ2R+oAQAhAgAuAAQKfy4ABAwACQk8JPsAAJoDAAwACQk8JPsAAJoDABcABwnoHiMWACwCAA4ABQmVHp80AEUBAAAA.Thrilling:BAAALgAECgcJBwAAAA==.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAACLgAFFH8IAAMYAAIJFw51EwBeAAAbAAIJFw5YkQCQAAAYAAIJggh1EwBeAAAuAAQKfzgAAxsACQkCHlscAJsCABsACQkCHlscAJsCABgAAgmMDuQ9AGUAAAAA.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAABLgAECn8lAAMYAAgJfgwMIAATAQAYAAgJfgwMIAATAQAbAAMJHgoB/gCYAAAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tidy:BAAALgAECgEJAQAAAA==.Tigg:BAAALgAECgkJCgAAAA==.Tiimmyy:BAAALgAECgYJDwAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDwAAAA==.Tinkertotem:BAAALgADCgkJCQAAAA==.Tinyandcute:BAAALgAECgMJBQABLgAECgkJHwAXAIocAA==.Tiravana:BAAALgAECgIJAgAAAA==.',
To='Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgAECgQJBAABLgAECggJGwAIACkTAA==.',
Tr='Trebuchet:BAABLgAECn8hAAMTAAkJuRQfNQAqAgATAAkJuRQfNQAqAgAlAAMJRAXHEQB0AAAAAA==.Treebarks:BAAALgADCgQJBgAAAA==.Treefrog:BAAALgADCgkJDAAAAA==.Treeshine:BAAALgAECgcJAQABLgAECggJGAANANkVAA==.Trtmiles:BAAALgAECgcJDwAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAABLgAECn8gAAIDAAgJNCKTIgCTAgADAAgJNCKTIgCTAgAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgQJEQAAAA==.',
Ub='Ubeenbained:BAABLgAECn82AAIZAAkJKBH5GAC6AQAZAAkJKBH5GAC6AQAAAA==.',
Uc='Ucme:BAAALgADCgUJBwAAAA==.',
Ud='Udderlyrich:BAAALgAECgEJAQAAAA==.',
Uh='Uhaw:BAABLgAECn8XAAMmAAYJuglUAgCLAAATAAYJugnXzQDsAAAmAAUJOAZUAgCLAAAAAA==.',
Un='Unlock:BAABLgAECn8bAAISAAkJYxoDIQBiAgASAAkJYxoDIQBiAgAAAA==.',
Ur='Urgmathron:BAABLgAECn8gAAIYAAgJZCOpBACvAgAYAAgJZCOpBACvAgAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Vadr:BAAALgAECgQJBgAAAA==.Valadashora:BAAALgAECgEJAQAAAA==.Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8ZAAMBAAcJMAVtHgB9AQABAAcJMAVtHgB9AQACAAQJnRKgDAAhAQAuAAQKfyUAAwIACQm8IF8KALkCAAIACQm8IF8KALkCAAEAAQlsGejMAD8AAAAA.Vanthyle:BAAALgAECgQJBAAAAA==.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgAECgQJEQAAAA==.',
Vd='Vdr:BAAALgADCgEJAgAAAA==.',
Ve='Velantheron:BAAALgAECgYJDQAAAA==.Velosityy:BAAALgAECgQJBQAAAA==.Vezrx:BAAALgAFFAIJAwAAAA==.',
Vi='Vinsmoke:BAABLgAECn8UAAIDAAYJrwv6yAD8AAADAAYJrwv6yAD8AAAAAA==.Vitanimm:BAAALgADCgIJAwAAAA==.Vitiate:BAAALgAECgYJBgAAAA==.Vixianna:BAAALgAECgEJAgAAAA==.',
Vo='Voinox:BAAALgADCgcJDQABLgADCgcJEwAFAAAAAA==.Volcanoez:BAAALgAECgQJDwAAAA==.Voltranian:BAAALgAECgEJAgAAAA==.',
Vr='Vrezor:BAABLgAECn8WAAITAAYJ0wU9/ACxAAATAAYJ0wU9/ACxAAAAAA==.',
Vy='Vyolnc:BAAALgAECgQJCAAAAA==.Vyrexiona:BAABLgAECn8YAAMQAAcJ2BmDGAAMAgAQAAcJ2BmDGAAMAgARAAEJtwIURgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgcJDAAAAA==.',
Wa='Warorgen:BAAALgADCgcJFwAAAA==.Warthelian:BAAALgADCgcJBwABLgAECgcJGQASAOcYAA==.',
Wh='Whatasham:BAAALgAFFAIJAwAAAA==.Whiskeytf:BAAALgADCgEJAQAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAIbAAgJ2hwnJQCSAgAbAAgJ2hwnJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECgkJEgAAAA==.',
Wo='Wokthisway:BAAALgAECgQJCAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wrathorn:BAAALgADCgYJBgAAAA==.Wreck:BAAALgADCgYJBgABLgAECgEJEgAFAAAAAA==.',
Wy='Wych:BAABLgAECn8VAAMYAAYJBhd6JADxAAAbAAYJvRU4swAaAQAYAAQJBRV6JADxAAAAAA==.Wynain:BAAALgADCgUJBQAAAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAABLgAECn8UAAILAAYJ+QkmWwDlAAALAAYJ+QkmWwDlAAAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yappor:BAABLgAECn8VAAIbAAgJuxQyWQDBAQAbAAgJuxQyWQDBAQAAAA==.',
Ye='Yekteniya:BAAALgAECgYJCwAAAA==.Yerrback:BAAALgAECgUJBwABLgAECgYJCwAFAAAAAA==.',
Yi='Yibbers:BAAALgADCgIJAgAAAA==.Yiimmyy:BAAALgAECgMJBAAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yunô:BAAALgAECgEJAQAAAA==.Yur:BAAALgADCgcJDAABLgAECgkJIQAGAGQiAA==.Yutch:BAAALgAECgYJEAAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAABLgAECn8bAAMKAAcJaAy3FQD8AAAKAAcJaAy3FQD8AAAJAAIJrAM0LAE8AAAAAA==.Zakkydrakky:BAABLgAECn8iAAMoAAkJIQ31FwBSAQAoAAgJLg31FwBSAQAQAAYJPggzWADSAAAAAA==.Zani:BAAALgAECgIJAgAAAA==.Zarashara:BAABLgAECn8lAAMgAAgJFBQ2LABYAQAgAAcJERY2LABYAQAfAAgJcQifPAAOAQAAAA==.',
Ze='Zeddoc:BAEALgADCggJCAABLgAECgQJCQAFAAAAAA==.Zedward:BAEALgAECgQJCQAAAA==.Zelta:BAAALgADCgkJEwAAAA==.Zeraxhul:BAAALgAECgEJAgAAAA==.Zergio:BAAALgADCgkJCAAAAA==.Zerise:BAAALgAECgUJCwAAAA==.',
Zo='Zolidus:BAAALgAECgYJEAAAAA==.Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAFFAMJBAAFAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8jAAIbAAkJKBL3aQCbAQAbAAkJKBL3aQCbAQAAAA==.Zun:BAAALgAECggJDQAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Èz']='Èzili:BAAALgAECgYJCwAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMTAAgJRRRZVgDuAQATAAgJ/BJZVgDuAQAlAAUJxAzNIwCxAAAAAA==.',
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
