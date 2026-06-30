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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Mage-Frost','Hunter-Marksmanship','Unknown-Unknown','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Priest-Discipline','DemonHunter-Devourer','Priest-Shadow','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','DeathKnight-Unholy','Mage-Arcane','Druid-Guardian','Monk-Mistweaver','Priest-Holy','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Rogue-Subtlety','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAABLgAECn8hAAMBAAgJcw93BgAZAQABAAgJcw93BgAZAQACAAIJRAillABLAAAAAA==.Aaramis:BAACLgAFFH8RAAIBAAMJqQ5gGgB/AAABAAMJqQ5gGgB/AAAuAAQKfzkAAgEACQmeGbMiAD4CAAEACQmeGbMiAD4CAAAA.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ac='Achin:BAAALgADCgUJBQAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelanthir:BAAALgAECgQJBAAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAABLgAECn8UAAIDAAgJEwRTxAADAQADAAgJEwRTxAADAQAAAA==.',
Ag='Aggrodk:BAAALgAECgIJAgAAAA==.',
Ah='Ahchu:BAAALgAECgIJAgAAAA==.Ahiru:BAAALgAECgMJAwAAAA==.',
Ai='Aidoffhealer:BAAALgAECgUJCwAAAA==.',
Al='Alariah:BAAALgAFFAMJDAAAAQ==.Alaín:BAABLgAECn8jAAIEAAgJuBj6CwCmAQAEAAgJuBj6CwCmAQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgAFAAAAAA==.Aldoraline:BAAALgADCgQJBgAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQABLgAECgEJAgAFAAAAAA==.Alystair:BAAALgADCgQJCAABLgAECgkJIQAGAGQiAA==.',
Am='Ambellina:BAAALgAECgYJDgAAAA==.Ampse:BAAALgAECgUJCAAAAA==.Amzy:BAAALgADCgYJCQABLgAECgEJAQAFAAAAAA==.',
An='Anaria:BAAALgAECggJEAAAAA==.Andirn:BAAALgAECggJDwAAAA==.Andorai:BAAALgAECgQJBgAAAA==.Angbu:BAABLgAECn8iAAMHAAcJQRcZFQBsAQAHAAcJQRcZFQBsAQACAAEJoARgkQAmAAAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Aphadiri:BAAALgAECgMJBAAAAA==.Apinkninja:BAACLgAFFH8FAAIDAAMJDgx+jQC+AAADAAMJDgx+jQC+AAAuAAQKfycAAgMABwkbGuR0AJABAAMABwkbGuR0AJABAAAA.',
Ar='Aranyssa:BAABLgAECn8hAAQIAAkJ1h8UCwCsAQAIAAYJhSAUCwCsAQAJAAYJ3hGPrQDoAAAKAAQJLhpvIQCjAAAAAA==.Arch:BAAALgAECgIJAgABLgAFFAYJHQAJAB4lAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAABLgAFFH8LAAILAAMJSgtcEwCJAAALAAMJSgtcEwCJAAAAAA==.Ardur:BAAALgAECgMJAwAAAA==.Ark:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Arkork:BAAALgAECgEJAgAAAA==.Arnøld:BAABLgAFFH8GAAIMAAMJ5gkYNwCuAAAMAAMJ5gkYNwCuAAAAAA==.Arruna:BAABLgAECn8XAAINAAcJTRGejgADAQANAAcJTRGejgADAQAAAA==.Artorìas:BAAALgADCgkJCwABLgAECgkJIQAGAGQiAA==.',
As='Asham:BAACLgAFFH8FAAIMAAMJtgclNwCuAAAMAAMJtgclNwCuAAAuAAQKf0QAAwwACQmkEqMVAC0CAAwACQmkEqMVAC0CAA4AAgnNCxpyAF0AAAAA.Ashenbloom:BAABLgAECn8nAAIPAAgJigm6XQAdAQAPAAgJigm6XQAdAQAAAA==.Asherin:BAAALgADCgYJBwAAAA==.Asiago:BAABLgAECn8XAAMQAAkJ4BIgLQBYAQAQAAkJ4BIgLQBYAQARAAEJRge0PwAxAAABLgAFFAEJAQAFAAAAAA==.Aspect:BAABLgAECn8hAAMGAAkJZCKLAAARAwAGAAkJZCKLAAARAwADAAEJWRLEYAE/AAAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgAECgQJBgAAAA==.',
Av='Avacúma:BAAALgAECgIJAwAAAA==.Avvalethra:BAABLgAECn9FAAMSAAkJeB4FFQCrAgASAAkJeB4FFQCrAgAEAAgJqg3XOwBwAQAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgcJDAAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAkJIgARACoeAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Babyball:BAAALgAECggJDAAAAA==.Bachshots:BAABLgAFFH8OAAISAAUJvxGvQgAoAQASAAUJvxGvQgAoAQAAAA==.Backstabbath:BAAALgAECgYJBgABLgAFFAMJCAASALkEAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgYJDgABLgAFFAQJDAATAOISAA==.Baineofagony:BAAALgADCgEJAQABLgAECgMJBQAFAAAAAA==.Bainesaur:BAAALgAECgEJAQAAAA==.Bainey:BAAALgADCgIJAgABLgAECgMJBQAFAAAAAA==.Bananataffy:BAABLgAECn8bAAIPAAcJWhRSPACiAQAPAAcJWhRSPACiAQAAAA==.Barackoshama:BAABLgAECn8eAAICAAkJAxwYHwDqAQACAAkJAxwYHwDqAQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Barrymarino:BAAALgAECgEJAQAAAA==.Basedween:BAAALgADCgcJGAAAAA==.Batialexism:BAAALgAECgMJAwAAAA==.Battlescars:BAAALgAFFAIJAgAAAA==.Baw:BAABLgAECn88AAMDAAkJ6R68GQC/AgADAAkJ6R68GQC/AgAUAAMJFwmTFQBvAAAAAA==.',
Be='Bearelf:BAAALgAECgMJAwAAAA==.Bearlinwall:BAABLgAECn8eAAIVAAYJARLYLAD8AAAVAAYJARLYLAD8AAAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Beladori:BAAALgAECgMJAwAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.Bews:BAABLgAFFH8GAAIWAAMJCRp0MwDgAAAWAAMJCRp0MwDgAAAAAA==.',
Bi='Bigbuns:BAAALgAECgEJAQABLgAECgkJHwAXAIocAA==.Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigdumbo:BAAALgAECgQJBQABLgAFFAMJBQABAOwbAA==.Bigskydh:BAAALgAECgYJEAAAAA==.Bigskymage:BAAALgAFFAIJAwAAAA==.Bigskymoney:BAAALgAFFAMJAwAAAA==.Billybones:BAABLgAECn8bAAITAAgJWwYwwgD7AAATAAgJWwYwwgD7AAAAAA==.Bip:BAAALgADCgEJAQAAAA==.Birde:BAAALgADCgcJBwABLgADCggJDQAFAAAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAECgkJFAABAI4WAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECggJJQAYAH4MAA==.Bladedozzer:BAAALgAECggJCwAAAA==.Blindinglite:BAACLgAFFH8TAAIZAAQJNB+yCAB9AQAZAAQJNB+yCAB9AQAuAAQKfyUAAhkACAl7IrwOADoCABkACAl7IrwOADoCAAAA.Blindtoast:BAAALgAECgIJAgAAAA==.Blkpriest:BAAALgAECgIJAwAAAA==.Bloodhaze:BAACLgAFFH8OAAIZAAQJ2yJxCACAAQAZAAQJ2yJxCACAAQAuAAQKfyAAAhkACQmjHxgLAK8CABkACQmjHxgLAK8CAAAA.Bloodyfel:BAAALgAECgEJAQAAAA==.Blorp:BAACLgAFFH8ZAAMNAAQJihhHQgAhAQANAAQJihhHQgAhAQAaAAEJuQjEBQA3AAAuAAQKfyIAAw0ACAnTHcwlAHACAA0ACAnfHMwlAHACABoABQlYHoUBAAsBAAEuAAUUBQkgABsA/yAA.',
Bo='Bodizzle:BAAALgAECgEJAwAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgQJCQABLgAFFAUJIAAbAP8gAA==.Borestus:BAABLgAECn8YAAIcAAcJpA7nngA5AQAcAAcJpA7nngA5AQAAAA==.Bouldur:BAABLgAECn8ZAAQLAAYJvAryWADrAAALAAYJJwnyWADrAAAdAAQJLAjjTwCTAAAeAAEJzgKuYQAWAAAAAA==.Bownystark:BAABLgAECn8eAAIEAAcJCCJHFQCIAgAEAAcJCCJHFQCIAgAAAA==.Bozz:BAAALgAECgQJBQAAAA==.',
Br='Brickingit:BAAALgAECgYJCwAAAA==.Brieter:BAAALgAECgcJDAABLgAFFAEJAQAFAAAAAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokendrako:BAABLgAFFH8GAAIVAAQJXQT9IwCLAAAVAAQJXQT9IwCLAAAAAA==.Brokikobo:BAAALgADCggJCwAAAA==.Broly:BAAALgAECgEJAQAAAA==.Bromthelian:BAAALgADCgkJCQABLgAECgcJGQASAOcYAA==.Broughston:BAAALgAECgEJAQAAAA==.Brutusx:BAABLgAECn8kAAISAAkJIw6RTAC8AQASAAkJIw6RTAC8AQAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAABLgAECn8oAAMVAAgJpCAwBwCEAgAVAAgJpCAwBwCEAgAfAAQJNQZNRABTAAAAAA==.Burntcring:BAAALgAECgUJCwAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJDgAAAA==.',
Bx='Bxxberry:BAABLgAECn8aAAQJAAcJPwW2yQC9AAAJAAYJ9QW2yQC9AAAIAAQJBwLFMABcAAAKAAMJPwO9NQBMAAAAAA==.',
Ca='Calari:BAAALgADCgEJAQAAAA==.Calculated:BAAALgAECgYJCAABLgAECgkJHwAXAIocAA==.Camipriest:BAAALgAECgEJAQAAAA==.Camishami:BAAALgADCgMJAwAAAA==.Cara:BAAALgAFFAMJBAABLgAFFAUJEgATAOolAA==.Carllina:BAAALgAECgYJBgAAAA==.Carmane:BAAALgAECgUJBQAAAA==.Casstyelle:BAAALgAECgQJCAABLgAECggJGwAIACkTAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgUJCgABLgAECgkJIQAIANYfAA==.Cet:BAAALgAECgQJBAABLgAECgkJIQAGAGQiAA==.Cexiback:BAABLgAFFH8FAAINAAMJjQ6sGgDBAAANAAMJjQ6sGgDBAAAAAA==.',
Ch='Chairon:BAAALgAECgQJBAABLgAFFAMJAwAFAAAAAA==.Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheebsz:BAAALgAECgUJBgAAAA==.Cheesus:BAAALgAFFAEJAQAAAA==.Chicharon:BAAALgAECgUJDwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECgkJHwAXAIocAA==.Chipsnsalsa:BAAALgAECgQJBAABLgAECgkJHwAXAIocAA==.Chocoriffic:BAABLgAECn8fAAIXAAkJihxkCwCwAgAXAAkJihxkCwCwAgAAAA==.Chokoballs:BAAALgAECgEJAQABLgAFFAMJCQATABsRAA==.Chokoballz:BAABLgAECn8gAAMgAAgJgR1LEABIAgAgAAgJoxxLEABIAgAhAAUJ3BrVMgA1AQABLgAFFAMJCQATABsRAA==.Churva:BAAALgAECgEJAgABLgAECgkJGgANAHwJAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAACLgAFFH8KAAMVAAMJhR9oDwAPAQAVAAMJhR9oDwAPAQAfAAEJHAvEIAA3AAAuAAQKfy4AAxUACQlJHzkEANcCABUACQlJHzkEANcCAB8AAQnEEX9SADQAAAAA.Coldbrewz:BAAALgAECgYJDwAAAA==.Conalbegle:BAAALgAECgUJCwAAAA==.Condensation:BAAALgADCgEJAQAAAA==.Coopah:BAAALgAECgkJBQAAAA==.Corgibutts:BAAALgAFFAIJAgAAAA==.Corvyr:BAAALgAECgIJAgAAAA==.Cowtee:BAAALgAFFAIJAwAAAA==.',
Cr='Crackjones:BAAALgAECgcJDAAAAA==.Crapsrocks:BAAALgAECgYJCgAAAA==.Crazydave:BAABLgAECn8aAAIXAAkJ7xEoIwDMAQAXAAkJ7xEoIwDMAQAAAA==.Creemywitchu:BAAALgAECgQJBQAAAA==.Crisgmt:BAAALgAECgcJDQAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAABLgAECn8XAAIWAAgJ2RvTGgBCAgAWAAgJ2RvTGgBCAgAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Crul:BAAALgAECgYJBgAAAA==.Cryptìc:BAACLgAFFH8VAAIOAAcJ+hkMBwACAgAOAAcJ+hkMBwACAgAuAAQKfyIAAg4ACQn2IxcDADIDAA4ACQn2IxcDADIDAAEuAAUUBgkXAAMABRkA.Cryptîc:BAACLgAFFH8XAAIDAAYJBRl1NQCTAQADAAYJBRl1NQCTAQAuAAQKfzAAAgMACAnSJcMZAL8CAAMACAnSJcMZAL8CAAAA.Cráckjones:BAAALgAECgEJAQAAAA==.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8YAAIDAAcJjxlOXwAdAgADAAcJjxlOXwAdAgAAAA==.Dabbia:BAACLgAFFH8NAAQIAAYJtRZcDgChAAAJAAQJ1Q8UWAAXAQAIAAMJ/RpcDgChAAAKAAIJnBn2BQBeAAAuAAQKfygABAgACAmoHpkIAN4BAAgABgl/IJkIAN4BAAkABgmPG5JXAMEBAAoABgnlGgkTALMBAAAA.Daedleus:BAAALgAECgUJBgAAAA==.Dalsam:BAAALgAECgEJAQAAAA==.Damented:BAABLgAECn8bAAMIAAgJKRP2DgBtAQAIAAgJKRP2DgBtAQAJAAMJyw984gCXAAAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnchild:BAAALgADCgEJAgABLgAECgYJHwABALMSAA==.Dawnpaw:BAABLgAECn8iAAMWAAkJqhNaIgCgAQAWAAgJcxFaIgCgAQAgAAUJpBUyRADuAAAAAA==.Daymonesus:BAAALgAECgUJBQAAAA==.',
De='Deadvocate:BAAALgADCgMJAwAAAA==.Deathballz:BAACLgAFFH8JAAITAAMJGxGZOQB9AAATAAMJGxGZOQB9AAAuAAQKfzYAAhMACQl8GBM6ABgCABMACQl8GBM6ABgCAAAA.Deathsbreach:BAABLgAECn8ZAAINAAgJpREVZQBdAQANAAgJpREVZQBdAQAAAA==.Deathsmite:BAAALgAECgIJBAAAAA==.Deathtee:BAABLgAECn8YAAITAAgJrxxPRgAiAgATAAgJrxxPRgAiAgABLgAFFAMJBQAbAP4ZAA==.Deavocate:BAAALgAECgEJAQAAAA==.Dedbeef:BAAALgAECgcJBwABLgAFFAEJAQAFAAAAAA==.Deepwaters:BAAALgADCgcJDgAAAA==.Deezhands:BAAALgADCgYJCwAAAA==.Dekuslice:BAABLgAECn8gAAIiAAkJyBSTJQCfAQAiAAkJyBSTJQCfAQAAAA==.Delafant:BAAALgAECgYJCwAAAA==.Deldaris:BAAALgAECgMJBAAAAA==.Delthrus:BAAALgADCgYJBgABLgAECgkJLwAeAPEYAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonarc:BAAALgAECgYJBwAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Deposate:BAAALgAECgEJBQAAAA==.Derpyderp:BAAALgAECgUJBwABLgAFFAMJCAADAJMGAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgAFAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAABLgAECn8VAAMWAAYJnRs4BABxAQAWAAYJnRs4BABxAQAgAAEJbA9foQAvAAAAAA==.Devonate:BAAALgAECgIJAwAAAA==.',
Di='Diatomaceous:BAAALgAECgEJAQAAAA==.Dinkys:BAAALgADCgYJCwABLgAECgYJDwAFAAAAAA==.Dinsum:BAAALgADCgkJJQAAAA==.Diogenist:BAAALgAECgYJCwAAAA==.Dirtydhunter:BAAALgAECgYJBgAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAABLgAFFH8KAAITAAMJDSMXGQAMAQATAAMJDSMXGQAMAQABLgAFFAMJDgAjACMmAA==.',
Dn='Dnaldtrump:BAAALgAECgQJBQAAAA==.',
Do='Dogdad:BAAALgADCgcJCwAAAA==.Doktarboom:BAAALgAECgMJAwAAAA==.Doktardoodad:BAAALgAECgcJDgAAAA==.Doktartides:BAAALgAECgEJAQAAAA==.Doktarzen:BAAALgAECgQJBgAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Donkypunch:BAAALgAECgUJBQAAAA==.Donut:BAAALgAECgUJCAAAAA==.Doomslayer:BAABLgAECn8aAAINAAkJfAn0YgB4AQANAAkJfAn0YgB4AQAAAA==.Doresearch:BAABLgAECn8iAAICAAgJkBU4LwCEAQACAAgJkBU4LwCEAQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAABLgAECn8ZAAIJAAgJSh+CQADbAQAJAAgJSh+CQADbAQAAAA==.Dragontee:BAAALgADCgQJBAAAAA==.Drakarys:BAAALgAECgYJCwAAAA==.Drakex:BAAALgAECgUJBwAAAA==.Drakoswrath:BAAALgAECgUJBgAAAA==.Dreadarcane:BAAALgAECgEJAgAAAA==.Dreamyskull:BAAALgADCgQJAgAAAA==.Drengist:BAABLgAECn8zAAIhAAkJhRrZDgBNAgAhAAkJhRrZDgBNAgAAAA==.Drexybear:BAABLgAECn8vAAMEAAkJOCKjAQD/AgAEAAkJfiGjAQD/AgASAAgJdCF2JABRAgAAAA==.Drezbi:BAABLgAECn8UAAISAAUJhBjudwBQAQASAAUJhBjudwBQAQAAAA==.Droodmon:BAAALgAECgQJDwAAAA==.Drpally:BAAALgADCgEJAQAAAA==.Drpebbles:BAAALgAECgQJCwAAAA==.Druidskillz:BAAALgADCgEJAQAAAA==.Druisty:BAAALgAECgEJAQAAAA==.',
Du='Dulcineru:BAAALgAECgEJAQABLgAECgkJJgAOAMcHAA==.Dunbarth:BAABLgAECn8jAAIcAAkJbg1WhQBlAQAcAAkJbg1WhQBlAQAAAA==.Durzaman:BAAALgAECgYJDQAAAA==.Durzuk:BAAALgAECgMJAwAAAA==.Duskhoof:BAAALgADCgIJAwAAAA==.',
Dy='Dynastyy:BAAALgAECgkJBwAAAA==.',
['Dé']='Dévílyñ:BAABLgAECn8qAAIJAAkJVguyWgCOAQAJAAkJVguyWgCOAQAAAA==.',
['Dí']='Díscordía:BAAALgAECgEJAQABLgAECgkJSgAXAB8iAA==.',
['Dü']='Dük:BAABLgAECn8YAAMJAAcJjxHkmgAHAQAJAAYJMRLkmgAHAQAKAAIJZA5RTACIAAAAAA==.',
Ea='Earthdozzer:BAAALgAECgEJAQAAAA==.',
Ed='Edarkness:BAAALgADCggJCAAAAA==.Edarnir:BAAALgADCgYJCAAAAA==.Eddai:BAAALgAECgEJAQAAAA==.',
Ef='Eff:BAACLgAFFH8KAAIjAAQJtwcXDADNAAAjAAQJtwcXDADNAAAuAAQKfxoAAiMACQmSDyQYANkBACMACQmSDyQYANkBAAAA.',
Eg='Eggy:BAAALgAECgkJDgAAAA==.',
Ek='Eks:BAAALgADCgkJKwAAAA==.',
El='Eldraaqeyn:BAAALgAECgMJAwAAAA==.Electrcfrost:BAAALgAECgEJAQAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elishii:BAAALgADCgYJBgAAAA==.Elkanàh:BAAALgAFFAEJAgABLgAFFAMJBQAPAE0MAA==.Ell:BAAALgADCgEJAQAAAA==.Elleynle:BAABLgAECn8VAAIEAAYJExEzFQASAQAEAAYJExEzFQASAQAAAA==.Elorene:BAAALgAECgkJAQAAAA==.Elunara:BAACLgAFFH8lAAIVAAUJ9hvWCgBFAQAVAAUJ9hvWCgBFAQAuAAQKf2sAAhUACQkmIjkDAPcCABUACQkmIjkDAPcCAAEuAAQKCQkhAAgA1h8A.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.Emptor:BAAALgAECgEJAQAAAA==.Emreezus:BAABLgAFFH8JAAITAAUJ3whvGAAQAQATAAUJ3whvGAAQAQABLgAFFAUJIgAcAO4gAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.Enigmä:BAAALgADCgYJCgAAAA==.Enio:BAAALgAECgMJAwAAAA==.',
Er='Ericuh:BAABLgAECn8fAAMBAAYJsxKEaAAiAQABAAYJsxKEaAAiAQACAAEJjAeCugAiAAAAAA==.',
Es='Escanör:BAAALgAECgYJEAABLgAECgkJIQAGAGQiAA==.Essekk:BAACLgAFFH8ZAAIDAAUJcRxvTABHAQADAAUJcRxvTABHAQAuAAQKfy8AAgMACQklH2AWACMDAAMACQklH2AWACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Event:BAAALgADCgUJBQAAAA==.Evodrak:BAAALgADCgYJBwAAAA==.Evokeeznutz:BAAALgAECgcJCQABLgAFFAQJEQAIAE4dAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.Exhaustion:BAAALgADCgIJAgAAAA==.Exploreswag:BAAALgAECgcJDwAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.',
['Eí']='Eír:BAAALgAECgYJCwABLgAECgkJSgAXAB8iAA==.',
Fa='Fairyholy:BAAALgADCgIJAgAAAA==.Faith:BAAALgAECgYJBwAAAA==.Fallenchaos:BAAALgAECgYJBgAAAA==.Famjam:BAABLgAECn8YAAMcAAkJRhMZwAAIAQAcAAcJQxEZwAAIAQAYAAMJKBh+KADTAAAAAA==.Fao:BAAALgAECgQJBQAAAA==.Fastrialimas:BAAALgAECgcJDQAAAA==.Fatigue:BAAALgAECgIJAgAAAA==.Fatpo:BAABLgAECn8mAAMXAAgJzSC6BgDiAgAXAAgJzSC6BgDiAgAOAAUJsCKdJwCRAQABLgAFFAQJGAAWACAlAA==.Fayjhu:BAABLgAECn8mAAIDAAgJaAtTkQBVAQADAAgJaAtTkQBVAQAAAA==.',
Fe='Felwingz:BAAALgAECgEJAQAAAA==.Ferbos:BAAALgAECgIJAwAAAA==.Feylock:BAABLgAECn8UAAIJAAcJ7RDPmgAIAQAJAAcJ7RDPmgAIAQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgAECgYJEAAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAACLgAFFH8YAAIjAAUJBx9XEwByAQAjAAUJBx9XEwByAQAuAAQKfzIAAiMACQk9HtcLAGcCACMACQk9HtcLAGcCAAAA.',
Fr='Frigate:BAABLgAECn8YAAIDAAcJWgUS2QA/AQADAAcJWgUS2QA/AQAAAA==.Frihgate:BAABLgAECn8aAAISAAgJNhZ2MgDmAQASAAgJNhZ2MgDmAQAAAA==.Frizza:BAAALgAECgkJAQAAAA==.Frostbiteme:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frosteenie:BAAALgAECgEJAQAAAA==.Frostiebyte:BAAALgAECgkJAQAAAA==.Frostmyface:BAAALgAFFAIJAwAAAA==.Frozenbeard:BAAALgAECgcJEwAAAA==.',
Fu='Fugarra:BAAALgAECgYJDwABLgAFFAMJCAASALkEAA==.Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAACLgAFFH8GAAIhAAMJSR4TJQAVAQAhAAMJSR4TJQAVAQAuAAQKfxYAAiEACAl/IZkQADcCACEACAl/IZkQADcCAAAA.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgAECgcJCAAAAA==.Fuzi:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.Fuzybritches:BAAALgAECgQJBQABLgAECgcJCQAFAAAAAA==.',
Fy='Fyafya:BAAALgAFFAEJAQABLgAFFAgJHQAbAFobAA==.Fyah:BAACLgAFFH8FAAIcAAMJsxjOZgDhAAAcAAMJsxjOZgDhAAAuAAQKfxsAAhwACQmZIJ8xADoCABwACQmZIJ8xADoCAAEuAAUUCAkdABsAWhsA.Fyaza:BAAALgAECgcJCwABLgAFFAgJHQAbAFobAA==.',
Ga='Gaga:BAAALgAECgEJAQAAAA==.Gariantel:BAAALgAECgMJDQAAAA==.Garleck:BAAALgAECgYJCwAAAA==.Garou:BAABLgAECn87AAILAAgJRCLyAAA+AgALAAgJRCLyAAA+AgAAAA==.Gaygar:BAAALgADCgcJEwAAAA==.',
Ge='Geekyigneel:BAAALgAECgEJAQAAAA==.Geekylock:BAABLgAECn8UAAMJAAcJ+AbBDQB4AAAJAAYJ8AXBDQB4AAAKAAMJ1wQ7RgAgAAABLgAFFAEJAQAFAAAAAA==.Geekymage:BAAALgAFFAEJAQAAAA==.Geekyxgenome:BAAALgAECgYJCwABLgAFFAEJAQAFAAAAAA==.Genesis:BAABLgAFFH8LAAITAAMJrR24egAPAQATAAMJrR24egAPAQAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgYJEwAAAA==.Gerttie:BAAALgAECgUJCQAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gigabytch:BAAALgAFFAEJAQAAAA==.Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAgJOQAMAAggAA==.Gistlek:BAAALgAECggJBAAAAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAABLgAECn8cAAIIAAkJWgyyAACpAQAIAAkJWgyyAACpAQAAAA==.Gorehammer:BAABLgAECn8qAAITAAgJlxmHUAAAAgATAAgJlxmHUAAAAgAAAA==.Gorto:BAAALgAECgEJAQAAAA==.',
Gr='Grassmoker:BAAALgAECgcJDgAAAA==.Gravediger:BAAALgAECgcJEQAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Grek:BAACLgAFFH8NAAMeAAQJ6iKvCwBzAQAeAAQJ6iKvCwBzAQAdAAMJvQShLwCjAAAuAAQKfxYAAx4ABwn1HVQPAPMBAB4ABgkHI1QPAPMBAB0AAQmfBFuJAB4AAAAA.Gridxx:BAABLgAECn8WAAMiAAcJDhOeLwBhAQAiAAcJDhOeLwBhAQAfAAEJkARoYgAfAAAAAA==.Grief:BAAALgADCgEJAQAAAA==.Grievex:BAABLgAECn9UAAIcAAkJgQ3GBACGAQAcAAkJgQ3GBACGAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.Grimblefritz:BAAALgADCgMJAwAAAA==.Gronthar:BAAALgAECgEJAQAAAA==.',
['Gî']='Gîgâbussy:BAAALgAECgYJBgAAAA==.',
Ha='Haikuu:BAAALgAECgYJDwAAAA==.Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgMJBAAAAA==.Hanyu:BAACLgAFFH8GAAITAAMJhwbXNgCJAAATAAMJhwbXNgCJAAAuAAQKfxQAAhMACQnTEtRDAPcBABMACQnTEtRDAPcBAAAA.Haranar:BAAALgAECgEJAwAAAA==.Harkelem:BAAALgAECgkJAQAAAA==.Haydayy:BAAALgADCgYJBgAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healabae:BAAALgAECgkJCQABLgAECgEJAQAFAAAAAA==.Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAABLgAECn8hAAMXAAgJ6hYNGAAOAgAXAAgJ6hYNGAAOAgAMAAIJ4wMdcwBCAAAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Helionn:BAAALgAECgQJBQAAAA==.Hemobloom:BAAALgAECgIJAwABLgAFFAUJIgAcAO4gAA==.Hemolock:BAACLgAFFH8LAAIJAAQJbw4EWQAVAQAJAAQJbw4EWQAVAQAuAAQKfyIAAwkABglpG+9XAJUBAAkABglpG+9XAJUBAAoAAQkAAIhXAAAAAAEuAAUUBQkiABwA7iAA.Hemostasis:BAACLgAFFH8iAAIcAAUJ7iCkKgBiAQAcAAUJ7iCkKgBiAQAuAAQKfysABBwACQnwIM4eAI0CABwACQnwIM4eAI0CACQABAm8CZRqAIwAABgAAQksDpJSACsAAAAA.Herjä:BAABLgAECn9KAAQXAAkJHyJ8BAA6AwAXAAkJHyJ8BAA6AwAMAAYJrRNgJQBpAQAOAAEJJgrmjgAsAAAAAA==.Hexmora:BAAALgAECgEJAgAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.Hirok:BAAALgADCgYJBgAAAA==.',
Ho='Homeslice:BAAALgAECggJEQAAAA==.Hoocha:BAAALgADCgYJBgABLgAFFAQJEQAIAE4dAA==.Hoollymollyy:BAAALgAECgEJAQAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.Hotandcold:BAAALgAECgEJAgAAAA==.',
Hu='Hunterskillz:BAAALgAECgUJBQAAAA==.Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgYJBwAAAA==.Huun:BAACLgAFFH8JAAIbAAMJ9h0eGQAJAQAbAAMJ9h0eGQAJAQAuAAQKfzoAAhsACQmIH7wEAOACABsACQmIH7wEAOACAAAA.',
Hy='Hyasynthia:BAAALgAECgkJDgAAAA==.Hycindraeda:BAAALgAECgYJBwAAAA==.Hydrox:BAAALgAECgIJAgAAAA==.',
['Hú']='Húckleberry:BAAALgAECggJEAAAAA==.',
Ia='Iamgabrielsj:BAAALgAECgIJAgAAAA==.Iamnsfw:BAAALgAECgcJEgAAAA==.',
Ic='Icelcelance:BAABLgAFFH8WAAIDAAYJmxrcMACnAQADAAYJmxrcMACnAQAAAA==.',
Ih='Ihealu:BAAALgAECgEJAQAAAA==.',
Ii='Iionel:BAAALgAECgEJAwAAAA==.',
Il='Illestone:BAAALgAECgMJAwABLgAFFAIJCAAYABcOAA==.Illuminee:BAAALgAECgIJAgABLgAECgIJAgAFAAAAAA==.Illydan:BAABLgAECn8iAAMNAAkJFxuPGACCAgANAAkJFxuPGACCAgAZAAEJGAgVegAmAAAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn83AAIDAAkJPSAbFADhAgADAAkJPSAbFADhAgAAAA==.Impedup:BAAALgAECgUJBQAAAA==.',
In='Indigø:BAAALgAECgUJDgAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAFFAMJBAAFAAAAAA==.',
Ir='Irezufortips:BAAALgAECgcJCwABLgAFFAMJCAASALkEAA==.Ironhide:BAAALgAECgQJBAAAAA==.Ironshadow:BAAALgADCgEJAQAAAA==.Irrenadro:BAABLgAECn8XAAIcAAgJTQ6+fQB+AQAcAAgJTQ6+fQB+AQAAAA==.Irvainee:BAAALgAECgYJDAABLgAECgcJEQAFAAAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Iy='Iyahna:BAAALgAECgEJAgAAAA==.',
Ja='Jaarhai:BAAALgADCgEJAQAAAA==.Jadechaos:BAAALgAECgEJAQAAAA==.Jadireux:BAAALgAECgYJEgAAAA==.Jaelia:BAAALgADCgEJAQAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jandina:BAAALgAECgMJAwAAAA==.Jarnabas:BAAALgAECggJCgAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jiffypop:BAAALgADCgUJBQAAAA==.Jimboslice:BAAALgADCgcJBwAAAA==.Jimmyhoofa:BAAALgADCgkJDQAAAA==.Jingleparts:BAAALgAECgUJCwABLgAECgkJHwAXAIocAA==.',
Jo='Joes:BAABLgAECn8nAAMSAAgJnBZrYQCEAQASAAgJnBZrYQCEAQAEAAYJdQfzHwCwAAAAAA==.Jonesy:BAAALgAECgUJDAAAAA==.Jophiel:BAAALgADCgkJCwAAAA==.Jorath:BAAALgAECgUJBgABLgAFFAMJCAASALkEAA==.Jorkota:BAAALgADCgEJAQAAAA==.',
Ju='Juicygossip:BAAALgAECgYJBwAAAA==.Jujupowa:BAABLgAECn8kAAIcAAgJZwckrgAiAQAcAAgJZwckrgAiAQAAAA==.Junebug:BAAALgAECgQJBQAAAA==.Justicus:BAAALgADCgMJAwAAAA==.',
['Jë']='Jëssë:BAAALgAECgQJBAAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kaelthalar:BAAALgAECgMJAwABLgAFFAMJCQAcAMIgAA==.Kagal:BAABLgAECn8WAAIbAAgJ3RExDwDSAQAbAAgJ3RExDwDSAQAAAA==.Kaidan:BAABLgAECn8pAAISAAkJpBJDTQC6AQASAAkJpBJDTQC6AQAAAA==.Kaipriest:BAAALgAECgQJBAAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgQJBQAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAFFAQJDAAZAMQhAA==.Katanya:BAAALgAECgYJCwABLgAECgkJIQAIANYfAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8cAAISAAYJrxb3GAClAQASAAYJrxb3GAClAQAAAA==.Keftheals:BAAALgAECgkJCgAAAA==.Keiriline:BAABLgAECn86AAQlAAkJ3RlHCgDaAQAlAAkJzhlHCgDaAQAmAAUJlhFvMADfAAATAAEJYwC4qAEUAAAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAABLgAECn8mAAIbAAkJxhvPDgA+AgAbAAkJxhvPDgA+AgAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgYJCgAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.Khalysea:BAAALgADCgIJAgABLgAECgkJIQAIANYfAA==.',
Ki='Kiimari:BAAALgAECggJDAAAAA==.Killbreed:BAACLgAFFH8MAAIfAAQJlh6MBABzAQAfAAQJlh6MBABzAQAuAAQKfygAAh8ACAmcI10EALsCAB8ACAmcI10EALsCAAAA.Kinkster:BAAALgAECggJCgAAAA==.Kirinani:BAAALgAECgEJAQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knight:BAAALgAECgYJDAABLgAFFAUJEQAgABciAA==.Knugg:BAAALgAECgMJAwAAAA==.Knuggz:BAABLgAECn8rAAILAAkJbCC/CQDHAgALAAkJbCC/CQDHAgAAAA==.',
Ko='Kogori:BAAALgAECgEJAgAAAA==.Kolduna:BAAALgADCgUJBQAAAA==.Kornash:BAAALgADCgQJBAAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgAECgMJAwAAAA==.',
Kr='Krestaul:BAAALgAECgkJEgAAAA==.',
Ku='Kurthalan:BAAALgAECgQJDAAAAA==.Kuumaneko:BAACLgAFFH8XAAIJAAUJKh/VCACAAQAJAAUJKh/VCACAAQAuAAQKfzYAAwkACQlbISoKAP8CAAkACQlbISoKAP8CAAoABgmvBwwxAPUAAAAA.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJEgAAAA==.Kyledh:BAACLgAFFH8WAAINAAUJyx+tDQA2AQANAAUJyx+tDQA2AQAuAAQKfzwAAw0ACQkjJtEBAG0DAA0ACQkjJtEBAG0DABoAAQluIf8jAGIAAAAA.Kyletotems:BAABLgAFFH8TAAMHAAUJGSUPAwCqAQAHAAQJGSUPAwCqAQABAAQJsCIWCQAqAQAAAA==.Kyllgorre:BAAALgAECgEJAQAAAA==.Kynyine:BAAALgADCgcJCAAAAA==.Kyouki:BAAALgAECgQJBAAAAA==.',
['Kî']='Kîmahri:BAAALgADCgEJAQAAAA==.',
La='Lancee:BAAALgAECgcJCgAAAA==.Landridan:BAAALgAECgMJBQAAAA==.Lanstoll:BAAALgAECgkJDQAAAA==.Lanthin:BAAALgADCggJEgAAAA==.Larzoe:BAAALgAECgYJCQABLgAECgkJIgAZAOojAA==.Larzoh:BAABLgAECn8iAAMZAAkJ6iOkAwBGAwAZAAkJ6iOkAwBGAwANAAMJSw4s8QBdAAAAAA==.Lateesha:BAAALgAFFAIJAgAAAA==.Laudrup:BAAALgAECgEJAQAAAA==.Lawdhots:BAAALgAECgMJBAAAAA==.Laylaria:BAAALgADCgEJAQAAAA==.',
Le='Leanwushin:BAABLgAECn8WAAIBAAYJ2Q27CQDCAAABAAYJ2Q27CQDCAAAAAA==.Lee:BAAALgADCgYJBQABLgAFFAMJDAATAD0hAA==.Legadiaus:BAAALgAECggJCgAAAA==.Lemonheads:BAABLgAECn9NAAMMAAkJ8yC5AwBkAwAMAAkJ8yC5AwBkAwAOAAEJ4QEtagAjAAAAAA==.Lenardo:BAAALgADCgcJBwAAAA==.Lethargy:BAAALgAECgYJBgAAAA==.',
Li='Liaenara:BAAALgAECgEJAQAAAA==.Lidorila:BAAALgAECgMJAwAAAA==.Lightbranger:BAAALgAECgUJBAAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgcJCgABLgAECgYJFAALAPkJAA==.Lilplottwist:BAAALgAECgIJAgAAAA==.Lilwiz:BAABLgAECn8VAAIKAAUJBRXtFQD5AAAKAAUJBRXtFQD5AAAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Linnxd:BAAALgAECgIJAwABLgAECgMJBgAFAAAAAA==.Linnxs:BAAALgAECgIJBAABLgAECgMJBgAFAAAAAA==.Linnxvx:BAAALgAECgMJBgAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgMJBQAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgAFAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lokibalboa:BAAALgAECgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwAFAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgAFAAAAAA==.Loxley:BAAALgAECgYJDQAAAA==.',
Ls='Lshaman:BAABLgAFFH8FAAIBAAMJ7Bv5QQDeAAABAAMJ7Bv5QQDeAAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAABLgAECn8dAAIOAAgJnxTpIQC4AQAOAAgJnxTpIQC4AQAAAA==.Lugeyamnk:BAAALgAECgEJAQAAAA==.Lunahunter:BAAALgAECgEJAQAAAA==.Lunarcricket:BAAALgAECgUJCAABLgAFFAMJCQAYAKogAA==.Lustnbeiber:BAAALgAECgEJAQAAAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwAFAAAAAA==.',
Ly='Lyncha:BAAALgAECgcJCQABLgAFFAMJCQAYAKogAA==.Lynchà:BAACLgAFFH8JAAIYAAMJqiBcBgAaAQAYAAMJqiBcBgAaAQAuAAQKfzcAAhgACQlLJGABAD0DABgACQlLJGABAD0DAAAA.Lynchá:BAAALgADCgIJAgAAAA==.Lynchä:BAAALgADCgEJAQABLgAFFAMJCQAYAKogAA==.',
Ma='Maakun:BAABLgAECn8dAAQXAAcJ3gxoOwBNAQAXAAcJ2gdoOwBNAQAOAAUJ8wcWQAD2AAAMAAQJHg2rOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJDgABLgAECgUJBgAFAAAAAA==.Madette:BAAALgADCggJCAABLgAFFAgJOQAMAAggAA==.Mageapoug:BAAALgADCgcJBwABLgAFFAQJEwAZAHcZAA==.Magia:BAAALgAECgcJCwAAAA==.Magmalance:BAAALgAFFAEJAQABLgAECggJGQANAKURAA==.Mahoragga:BAAALgADCgYJBgAAAA==.Mahzad:BAACLgAFFH8OAAIBAAUJgyFDEwDMAQABAAUJgyFDEwDMAQAuAAQKfyYAAwEABwljIzoYAFQCAAEABwljIzoYAFQCAAIABgmmDdpWAOAAAAAA.Makaveli:BAAALgADCgkJEAAAAA==.Maladi:BAAALgADCgkJJAAAAA==.Malfrun:BAABLgAECn8vAAMeAAkJ8RhDCwA5AgAeAAkJ8RhDCwA5AgALAAMJdQZ4fgB8AAAAAA==.Manaena:BAAALgADCgQJAwAAAA==.Marinnite:BAAALgADCgYJDgAAAA==.Markzugrberg:BAAALgADCgkJCQAAAA==.Marox:BAACLgAFFH8IAAIDAAQJwgqzbgAFAQADAAQJwgqzbgAFAQAuAAQKfxgAAgMACQldHXZDAG4CAAMACQldHXZDAG4CAAAA.Marrøwgar:BAAALgAECggJEwABLgAECggJGQANAKURAA==.Marshmellows:BAAALgAECgYJBgABLgAECgYJHwABALMSAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAACLgAFFH8dAAIJAAYJHiWqGAD9AQAJAAYJHiWqGAD9AQAuAAQKfyMAAwkACQmGJEoVANUCAAkACAmGJEoVANUCAAoAAQkAANtVAG0AAAAA.Matooka:BAABLgAECn8yAAISAAkJXg1VTQC6AQASAAkJXg1VTQC6AQAAAA==.Maynji:BAAALgAECgMJAwAAAA==.Mayushi:BAAALgAECgYJCQAAAA==.',
Mc='Mcthugger:BAAALgAECgEJAQABLgAFFAIJCAAYABcOAA==.',
Me='Mebforu:BAAALgADCgEJAQAAAA==.Meencurry:BAABLgAECn8kAAIDAAgJghXZZgCvAQADAAgJghXZZgCvAQAAAA==.Megozugzug:BAAALgAFFAMJBAAAAA==.Meyneth:BAAALgAECgQJCAAAAA==.',
Mi='Mikaì:BAAALgAECgkJEgAAAA==.Mikehawkener:BAAALgAECgYJDwAAAA==.Mirlone:BAAALgAECgYJDAAAAA==.Misleading:BAABLgAECn8XAAIeAAUJNhgxJQAIAQAeAAUJNhgxJQAIAQAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Missdead:BAAALgAECgEJAQAAAA==.Mistfisting:BAACLgAFFH8HAAIWAAMJ8xV1OgC8AAAWAAMJ8xV1OgC8AAAuAAQKfxQAAhYABwmEHjIkAAACABYABwmEHjIkAAACAAAA.',
Mo='Moderato:BAAALgAECgkJDgAAAA==.Moelleri:BAABLgAECn8fAAITAAkJGhhDWQC6AQATAAkJGhhDWQC6AQAAAA==.Mojosmilês:BAAALgAECgQJBAAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgUJBgAFAAAAAA==.Molodeath:BAAALgAECgYJDQAAAA==.Mommÿ:BAACLgAFFH8OAAIMAAUJ0QvKIQBBAQAMAAUJ0QvKIQBBAQAuAAQKfyEAAwwACQkIFwkSAFYCAAwACQkIFwkSAFYCAA4AAQl0ABZtAAcAAAAA.Moneymage:BAAALgAECgcJCwAAAA==.Monkgroom:BAACLgAFFH8aAAIWAAUJGBCWKQAjAQAWAAUJGBCWKQAjAQAuAAQKfx0AAxYACQmaFA8XAAkCABYACQmaFA8XAAkCACAABgnyCto5ADYBAAAA.Monsignor:BAAALgAECgIJCwAAAA==.Montra:BAACLgAFFH8HAAIVAAMJ6g6lHgCkAAAVAAMJ6g6lHgCkAAAuAAQKfzMAAxUACQn6HHkGAJYCABUACQn6HHkGAJYCAB8ABQkCCf4eAOsAAAAA.Mooharahgha:BAAALgAECgEJAQAAAA==.Mordach:BAAALgAECgEJAwAAAA==.Moreilira:BAAALgAECgYJEQAAAA==.Morgaine:BAAALgADCgEJAQAAAA==.Mornshield:BAABLgAECn8jAAMcAAYJWxSmkQBZAQAcAAYJIxCmkQBZAQAYAAUJUxMIJgDZAAABLgAFFAMJCAASALkEAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motorinkashi:BAACLgAFFH8HAAIPAAMJfwp/SQCUAAAPAAMJfwp/SQCUAAAuAAQKfxoAAw8ACQnmHrQIAC0DAA8ACQnmHrQIAC0DABUAAwkXD7BNAHUAAAAA.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAABLgAECn8aAAIeAAgJoRTaGwBYAQAeAAgJoRTaGwBYAQAAAA==.Muddthir:BAAALgAECgQJBAABLgAECggJGgAeAKEUAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCwABLgAFFAUJIAAbAP8gAA==.Mustardmonk:BAAALgAECgEJAQABLgAFFAUJIAAbAP8gAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwAcANocAA==.',
Na='Nahaine:BAAALgADCggJCAAAAA==.Narf:BAAALgAECgEJAQAAAA==.Naronar:BAAALgAECgEJAwAAAA==.Nazrra:BAABLgAECn8bAAIeAAkJIxRkEAACAgAeAAkJIxRkEAACAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgAECgEJAQAAAA==.Nelorim:BAAALgAECgIJAgAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Nenad:BAAALgADCgEJAQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nerodic:BAAALgADCgYJBgABLgAFFAQJEwATAMgYAA==.Nestaah:BAAALgAFFAIJBAAAAA==.Nettra:BAAALgAECgIJCgAAAA==.Newtnewt:BAAALgAECgUJBgAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nicneven:BAAALgADCgkJCQAAAA==.Nininbrew:BAAALgAECgEJAwABLgAECgcJHAAMAGEUAA==.Nirath:BAABLgAECn88AAIDAAkJEhZZOQAzAgADAAkJEhZZOQAzAgAAAA==.',
No='Nobainer:BAAALgAECgMJBQAAAA==.Noed:BAAALgAECgMJBgAAAA==.Nohkana:BAAALgAECgEJAgAAAA==.Nohkano:BAACLgAFFH8MAAIhAAMJyyQJHgA6AQAhAAMJyyQJHgA6AQAuAAQKfzwAAiEACQn8JecAAGsDACEACQn8JecAAGsDAAAA.Nokinkshame:BAAALgAECgUJBQABLgAECgkJHwAXAIocAA==.Nokt:BAAALgADCgQJBAAAAA==.Noobymonk:BAAALgAECggJEwAAAA==.Noralise:BAAALgAECgYJEwAAAA==.Northerndk:BAABLgAECn8WAAITAAcJKgXE6QDIAAATAAcJKgXE6QDIAAAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgcJDwAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.Nutthunter:BAAALgAECgEJAwAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAIDAAgJVhTDbAD8AQADAAgJVhTDbAD8AQAAAA==.',
Oa='Oakmain:BAAALgAECgUJBQAAAA==.',
Oc='Octavarium:BAABLgAECn8hAAIWAAgJExy/FgBjAgAWAAgJExy/FgBjAgAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.Odinspriest:BAAALgADCgcJBwAAAA==.Odinsvulpera:BAAALgADCgYJBwAAAA==.',
Oe='Oennomaus:BAAALgAECgUJBgAAAA==.',
Of='Offspec:BAAALgAECgEJAgAAAA==.',
Oh='Ohyshii:BAAALgAECgMJBQAAAA==.',
Ol='Oldglory:BAAALgAECgcJCwAAAA==.Olorinziln:BAAALgAECgYJBgAAAA==.',
On='Oneshothel:BAABLgAECn8ZAAISAAcJ5xhHTQC6AQASAAcJ5xhHTQC6AQAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwAcANocAA==.',
Or='Orcpeon:BAABLgAECn8UAAISAAYJYg00lQAVAQASAAYJYg00lQAVAQABLgAECgkJRwAcABYhAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAABLgAECn8WAAMdAAYJmRYpEwByAQAdAAYJDxUpEwByAQALAAQJyRHGawAHAQABLgAECgkJHwAXAIocAA==.Overdoze:BAAALgAECgEJAQAAAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Paichan:BAAALgAECgEJAQAAAA==.Palakazam:BAAALgAFFAEJAQAAAA==.Palaweenie:BAAALgAECgEJAQAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgAECgQJCAAAAA==.Pancaked:BAAALgAECggJEwABLgAECgkJHwAXAIocAA==.Pangpang:BAAALgADCgIJAgAAAA==.Pantheons:BAAALgADCgIJAwAAAA==.Paradon:BAAALgADCgEJAQAAAA==.Paradox:BAAALgAECgQJBAABLgAFFAYJGwAfAAchAA==.Parsi:BAACLgAFFH8LAAIaAAMJDRfTCADGAAAaAAMJDRfTCADGAAAuAAQKfx0AAhoACQlKIFcCAN4CABoACQlKIFcCAN4CAAAA.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Pennywhys:BAAALgAECgEJAgAAAA==.Penut:BAAALgAECgEJAgAAAA==.Perritax:BAABLgAECn8iAAIDAAcJdhHcjgBaAQADAAcJdhHcjgBaAQAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwABLgAECgQJBQAFAAAAAA==.Phialrog:BAAALgAECgYJCwAAAA==.Phoebelyria:BAAALgAECgYJEwAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgAFAAAAAA==.',
Pi='Pickelz:BAAALgADCgMJAwAAAA==.Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgYJDAAAAA==.Pingdoo:BAAALgAECgIJAwAAAA==.Pingdu:BAAALgAECgEJAgAAAA==.Pingdui:BAAALgAECgEJAgAAAA==.Pingryun:BAAALgAECgEJAgAAAA==.Piptip:BAAALgADCgcJBwAAAA==.Pizzaparty:BAAALgAECgQJAwABLgAECgkJHwAXAIocAA==.',
Pl='Pletenko:BAAALgAECgEJAQAAAA==.',
Po='Pofat:BAACLgAFFH8YAAIWAAQJICVsHACPAQAWAAQJICVsHACPAQAuAAQKfxQAAxYACAkgHNkSAIYCABYACAkgHNkSAIYCACAAAgnWEZl1AGUAAAAA.Polis:BAABLgAECn9HAAMcAAkJFiHBDgDwAgAcAAkJFiHBDgDwAgAYAAcJGROMGABYAQAAAA==.Pomol:BAABLgAECn8VAAISAAcJDRf1SACPAQASAAcJDRf1SACPAQAAAA==.Pomoly:BAAALgAECgIJBAAAAA==.Poppafury:BAABLgAECn8ZAAIeAAcJJBWnGwBaAQAeAAcJJBWnGwBaAQAAAA==.Potent:BAABLgAECn8gAAMTAAgJ4RFOhQBZAQATAAgJ4RFOhQBZAQAmAAQJbQaPOgBvAAAAAA==.Poubear:BAAALgAECgcJCwABLgAFFAMJCAASALkEAA==.Pougadina:BAAALgAECgYJCAABLgAFFAQJGAAWACAlAA==.',
Pr='Primal:BAAALgADCgIJAgAAAA==.Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAACLgAFFH8IAAITAAMJ1gibtQC8AAATAAMJ1gibtQC8AAAuAAQKfxgAAxMACAn1FqldAK8BABMACAn1FqldAK8BACYAAQlLBH5PABcAAAAA.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAABLgAECn8YAAIDAAcJMwa5zgD0AAADAAcJMwa5zgD0AAABLgAFFAMJCAASALkEAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Qi='Qizzle:BAAALgADCgMJAwAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAIcAAYJYxbTigBlAQAcAAYJYxbTigBlAQAAAA==.Ramshunter:BAABLgAECn8fAAMSAAkJFiFcBwAaAwASAAkJFiFcBwAaAwAEAAIJ4xF0OAA9AAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgAECgUJCgAAAA==.Ratnob:BAABLgAECn8xAAITAAkJhhv3KgBUAgATAAkJhhv3KgBUAgAAAA==.Ravnaar:BAAALgAECgkJDwAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.Razzledazzl:BAABLgAECn8UAAIDAAcJnAsYCwD+AAADAAcJnAsYCwD+AAAAAA==.',
Re='Reddemon:BAAALgAFFAMJAwABLgAFFAQJDQAeAOoiAA==.Redstraw:BAAALgADCgYJBwAAAA==.Relda:BAAALgAFFAIJBAAAAA==.Remye:BAAALgAECgkJCgAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Renne:BAAALgAECggJCAAAAA==.Rennshi:BAACLgAFFH8MAAIZAAQJxCEfBAATAQAZAAQJxCEfBAATAQAuAAQKfyEAAhkACQlBJAgEADsDABkACQlBJAgEADsDAAAA.Retpally:BAABLgAFFH8QAAIeAAcJ7hRrCACwAQAeAAcJ7hRrCACwAQAAAA==.Reyikrat:BAAALgAECgQJCAAAAA==.Rezmee:BAACLgAFFH8IAAITAAMJJSWWfQALAQATAAMJJSWWfQALAQAuAAQKfxgAAhMACQmIIxMVAMkCABMACQmIIxMVAMkCAAAA.',
Rh='Rheaf:BAAALgAECgYJCQAAAA==.',
Ri='Riarina:BAAALgADCgQJBAAAAA==.Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8WAAIDAAcJPxGIvgBmAQADAAcJPxGIvgBmAQAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rolexiós:BAAALgADCgcJBwAAAA==.Rosario:BAACLgAFFH8gAAQbAAUJ/yD7CgBvAQAbAAUJ/yD7CgBvAQAEAAIJOQ1KHwCZAAASAAEJkxkHnABXAAAuAAQKf1QABBsACQl+JB0CADEDABsACQnqIx0CADEDAAQACAmhIakNANgCABIABAmrJORQALABAAAA.Royfan:BAAALgAECgQJBAAAAA==.',
Ry='Ryotwar:BAAALgAECgEJAgAAAA==.Rythmatic:BAACLgAFFH8OAAIjAAMJIyaaBgAwAQAjAAMJIyaaBgAwAQAuAAQKfysAAyMACQm/JToCADwDACMACQm/JToCADwDACcABgkNHgQJALUBAAAA.Ryvenox:BAAALgADCgcJBwAAAA==.',
['Ré']='Rénae:BAAALgAECgkJAgABLgAECgkJCAAFAAAAAA==.',
['Rò']='Ròwan:BAAALgADCgkJCQAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Sadcat:BAAALgADCgEJAQAAAA==.Sakieri:BAABLgAECn9cAAMOAAkJBCNrAADGAgAOAAkJBCNrAADGAgAXAAEJ3hANDQA1AAAAAA==.Salhasheals:BAAALgADCgMJAwAAAA==.Salinomycin:BAABLgAECn8UAAIPAAYJ5wffeADMAAAPAAYJ5wffeADMAAAAAA==.Saltyaf:BAAALgADCgMJAwAAAA==.Saltymcnalty:BAAALgAECgEJAQAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sanathas:BAAALgAECgUJBwAAAA==.Sandolorian:BAAALgAECggJDgAAAA==.Sandordel:BAAALgAECgQJBwAAAA==.Sangan:BAABLgAECn8pAAIDAAkJGyJxFwDMAgADAAkJGyJxFwDMAgAAAA==.Sanguini:BAACLgAFFH8HAAIDAAMJ0QpiiwDCAAADAAMJ0QpiiwDCAAAuAAQKfyoAAgMACQk4GHY8ACgCAAMACQk4GHY8ACgCAAAA.Satharan:BAAALgADCgEJAQAAAA==.Sathari:BAAALgAECgQJCAAAAA==.',
Sc='Scare:BAAALgAECgEJAQAAAA==.Schmelzen:BAACLgAFFH8LAAIDAAUJURcWVwAvAQADAAUJURcWVwAvAQAuAAQKfxUAAgMACQkzIrsLABsDAAMACQkzIrsLABsDAAAA.Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAFFAEJAQABLgAFFAMJBAAFAAAAAA==.Sebaz:BAAALgAECgMJBQAAAA==.Selaris:BAABLgAECn8UAAIcAAkJBxHBFQCCAAAcAAkJBxHBFQCCAAAAAA==.Selathviala:BAAALgADCgMJBQAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8iAAMRAAkJKh7JAQCDAQAQAAgJbBw9EQD2AQARAAQJmhvJAQCDAQAuAAQKfywAAxEACQnJIsEBAC8DABEACAlJI8EBAC8DABAACAlUIygKALYCAAAA.Sergregorsly:BAAALgAECggJDAAAAA==.Serintalis:BAAALgADCgYJBgAAAA==.',
Sh='Shadowblitzx:BAAALgAECgUJEAAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAFFAUJGAAjAAcfAA==.Shamthelian:BAAALgADCgUJBQABLgAECgcJGQASAOcYAA==.Shangan:BAAALgAECgEJAgAAAA==.Shapestalker:BAAALgADCgcJCgAAAA==.Sharana:BAAALgAECgQJCAAAAA==.Shazzie:BAAALgAECgQJCQAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shiftingsliz:BAAALgAECgEJAQAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgAECgYJCgAAAA==.Shirrazaha:BAAALgADCgcJBwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgABLgAFFAQJFQAUANkhAA==.',
Si='Silaris:BAAALgADCgMJBgAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Singx:BAAALgAECgkJAgAAAA==.Sinnur:BAAALgAECgQJCQAAAA==.Sinsear:BAAALgAECgUJBwAAAA==.',
Sk='Skeezer:BAABLgAFFH8RAAIIAAQJTh36AgBvAQAIAAQJTh36AgBvAQAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizz:BAAALgADCgYJBgAAAA==.Slizzie:BAAALgAECgYJDQAAAA==.Slizziore:BAAALgAECgEJAgAAAA==.Slizzle:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Slizzley:BAAALgAECgEJAgAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.Slycendyce:BAAALgAECgMJAwAAAA==.',
Sm='Smackdiver:BAAALgADCgYJAwAAAA==.Smarfus:BAAALgAECgYJCgABLgAFFAQJDQAeAOoiAA==.Smegspreader:BAAALgAECgEJBAAAAA==.Smilingp:BAAALgADCgkJDwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAABLgAECn8UAAIgAAYJdwM0aQCCAAAgAAYJdwM0aQCCAAAAAA==.Snarge:BAACLgAFFH8VAAIHAAcJBRP6AgCtAQAHAAcJBRP6AgCtAQAuAAQKfxkABAcACQkpGSAKADACAAcACQkpGSAKADACAAEABQlqCNGQALcAAAIAAQkjEsaDADsAAAAA.Sneaktee:BAAALgAFFAEJAgABLgAFFAMJBQAbAP4ZAA==.Snuggled:BAAALgAECgUJBgABLgAECgkJHwAXAIocAA==.',
So='Soone:BAAALgAECgkJAQAAAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Sparkydrac:BAAALgAECgYJBgABLgAECggJGQANAKURAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spness:BAAALgAECgUJBQAAAA==.Spunky:BAAALgAECgQJBwAAAA==.',
Sq='Sqquish:BAAALgAECgIJBQAAAA==.Squeaksune:BAAALgADCgcJCAAAAA==.Squiish:BAABLgAECn8hAAIDAAcJ6BFehQBsAQADAAcJ6BFehQBsAQAAAA==.',
Sr='Srorcalot:BAABLgAECn8XAAITAAkJWg3wXACxAQATAAkJWg3wXACxAQABLgAFFAMJCAASALkEAA==.',
St='Steamfitter:BAAALgADCgEJAQAAAA==.Steppedon:BAABLgAECn8gAAILAAcJLBLAOQBfAQALAAcJLBLAOQBfAQAAAA==.Steviewonder:BAAALgAECgQJBwAAAA==.Stingerai:BAACLgAFFH8FAAISAAMJnxB+IACvAAASAAMJnxB+IACvAAAuAAQKfx0AAhIACQmRIFEoAD0CABIACQmRIFEoAD0CAAEuAAUUAwkKABUAhR8A.Stingeret:BAAALgADCgMJAwABLgAFFAMJCgAVAIUfAA==.Stingerge:BAAALgAECgMJBAABLgAFFAMJCgAVAIUfAA==.Stormweaverr:BAAALgAFFAEJAQABLgAFFAQJDQAeAOoiAA==.',
Su='Sugurugeto:BAAALgADCgEJAQAAAA==.Sunbeamer:BAAALgAECgYJDwAAAA==.Sunnis:BAAALgAECgEJAQAAAA==.Sureman:BAAALgAECgMJBQAAAA==.Suun:BAAALgAECgcJEQAAAA==.',
Sw='Swaggie:BAAALgADCgQJBgAAAA==.Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylentsniper:BAABLgAFFH8IAAMSAAMJuQSbIwCeAAASAAMJuQSbIwCeAAAEAAEJmwAKPQAoAAAAAA==.Sylvesters:BAAALgADCgcJBwABLgAECgUJBgAFAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
['Sá']='Sága:BAAALgAECgEJAQAAAA==.',
Ta='Tacosalad:BAAALgAECgcJCwABLgAECgkJHwAXAIocAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Talinas:BAAALgADCgYJBgAAAA==.Tamb:BAABLgAECn8gAAIPAAYJwRRvUgBFAQAPAAYJwRRvUgBFAQAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tankndspank:BAAALgADCgYJBgAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Tark:BAAALgADCgYJBwAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwAFAAAAAA==.Tauntisoff:BAAALgADCgMJAwAAAA==.',
Tc='Tchittykitty:BAAALgAECgMJAwAAAA==.',
Te='Tecomonk:BAAALgADCgIJAgAAAA==.Tedious:BAAALgAECgYJEwAAAA==.Teehuntee:BAABLgAFFH8FAAIbAAMJ/hl0BwCvAAAbAAMJ/hl0BwCvAAAAAA==.Teepal:BAAALgAFFAEJAgABLgAFFAMJBQAbAP4ZAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAABLgAECn8tAAIHAAkJGh7IBwBNAgAHAAkJGh7IBwBNAgAAAA==.Teribullduce:BAACLgAFFH8ZAAIbAAUJehieBwCVAQAbAAUJehieBwCVAQAuAAQKf3wAAhsACQl6IPECABEDABsACQl6IPECABEDAAAA.Terscheckii:BAAALgAFFAIJBAAAAA==.',
Th='Thelian:BAAALgADCgMJAwABLgAECgcJGQASAOcYAA==.Theslimer:BAABLgAECn8aAAMSAAkJShoCJwBEAgASAAkJShoCJwBEAgAEAAYJpQqSVQDzAAAAAA==.Thesukuna:BAAALgAECgUJBwAAAA==.Thingol:BAAALgADCgkJJwAAAA==.Thormor:BAACLgAFFH85AAIMAAgJCCCoAQAhAgAMAAgJCCCoAQAhAgAuAAQKf0AABAwACQm5JQsAAPADAAwACQm5JQsAAPADABcABwnoHiMWACwCAA4ABQmVHp80AEUBAAAA.Thrilling:BAAALgAECgcJBwAAAA==.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAACLgAFFH8IAAMYAAIJFw52EwBeAAAcAAIJFw5WkQCQAAAYAAIJggh2EwBeAAAuAAQKfz4AAxwACQkGIOUCAO4BABwACQkGIOUCAO4BABgAAgmMDuQ9AGUAAAAA.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAABLgAECn8lAAMYAAgJfgwNIAATAQAYAAgJfgwNIAATAQAcAAMJHgoB/gCYAAAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tidy:BAAALgAECgEJAQAAAA==.Tigg:BAAALgAECgkJCwAAAA==.Tiimmyy:BAAALgAECgYJDwAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDwAAAA==.Tinkertotem:BAAALgADCgkJCQAAAA==.Tinyandcute:BAAALgAECgMJBQABLgAECgkJHwAXAIocAA==.Tiravana:BAAALgAECgIJAgAAAA==.',
To='Tokalor:BAAALgADCgEJAQAAAA==.Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgAECgQJBAABLgAECggJGwAIACkTAA==.',
Tr='Trebuchet:BAABLgAECn8hAAMTAAkJuRQgNQAqAgATAAkJuRQgNQAqAgAlAAMJRAXHEQB0AAAAAA==.Treebarks:BAAALgADCgQJBgAAAA==.Treefrog:BAAALgADCgkJDAAAAA==.Treeshine:BAAALgAECgcJAQABLgAECggJGAANANkVAA==.Trtmiles:BAAALgAECgcJDwAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAABLgAECn8hAAIDAAgJNCKSIgCTAgADAAgJNCKSIgCTAgAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgQJEQAAAA==.',
Ub='Ubeenbained:BAABLgAECn83AAIZAAkJKBH5GAC6AQAZAAkJKBH5GAC6AQAAAA==.',
Uc='Ucme:BAAALgADCgUJBwAAAA==.',
Ud='Udderlyrich:BAAALgAECgEJAQAAAA==.',
Uh='Uhaw:BAABLgAECn8XAAMmAAYJugnLBQCBAAATAAYJugnezQDsAAAmAAUJOAbLBQCBAAAAAA==.',
Un='Unlock:BAABLgAECn8bAAISAAkJYxoCIQBiAgASAAkJYxoCIQBiAgAAAA==.',
Ur='Urgmathron:BAABLgAECn8hAAIYAAkJ/CKpBACvAgAYAAkJ/CKpBACvAgAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Vadr:BAAALgAECgQJBgAAAA==.Valadashora:BAAALgAECgEJAQAAAA==.Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8aAAMBAAcJWwldHgB+AQABAAcJWwldHgB+AQACAAQJnRKgDAAhAQAuAAQKfyUAAwIACQm8IF8KALkCAAIACQm8IF8KALkCAAEAAQlsGejMAD8AAAAA.Valtier:BAAALgAECgEJAQAAAA==.Vansthir:BAAALgAECgkJAQAAAA==.Vanthyle:BAAALgAECgQJBAAAAA==.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgAECgQJEQAAAA==.',
Vd='Vdr:BAAALgADCgEJAgAAAA==.',
Ve='Velantheron:BAAALgAECgYJDQAAAA==.Velosityy:BAAALgAECgQJBQAAAA==.Vezrx:BAAALgAFFAIJAwAAAA==.',
Vi='Vinsmoke:BAABLgAECn8UAAIDAAYJrwsAyQD8AAADAAYJrwsAyQD8AAAAAA==.Vitanimm:BAAALgADCgIJAwAAAA==.Vitiate:BAAALgAECgYJBgAAAA==.Vixianna:BAAALgAECgEJAgAAAA==.',
Vo='Voinox:BAAALgADCgcJDQABLgADCgcJEwAFAAAAAA==.Volcanoez:BAAALgAECgQJDwAAAA==.Voltranian:BAAALgAECgEJAgAAAA==.',
Vr='Vrezor:BAABLgAECn8WAAITAAYJ0wVJ/ACxAAATAAYJ0wVJ/ACxAAAAAA==.',
Vy='Vyndrian:BAAALgADCgcJBgABLgAECggJCgAFAAAAAA==.Vyolnc:BAAALgAECgQJCAAAAA==.Vyrexiona:BAABLgAECn8YAAMQAAcJ2BmDGAAMAgAQAAcJ2BmDGAAMAgARAAEJtwIURgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgcJDAAAAA==.',
Wa='Warorgen:BAAALgADCgcJGgAAAA==.Warthelian:BAAALgADCgcJBwABLgAECgcJGQASAOcYAA==.',
Wh='Whatasham:BAAALgAFFAIJAwAAAA==.Whiskeytf:BAAALgADCgEJAQAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAIcAAgJ2hwnJQCSAgAcAAgJ2hwnJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECgkJEgAAAA==.',
Wo='Wokthisway:BAAALgAECgQJCAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wrathorn:BAAALgADCgYJBgAAAA==.Wreck:BAAALgADCgYJBgABLgAECgEJEgAFAAAAAA==.',
Wy='Wych:BAABLgAECn8VAAMYAAYJBhd6JADxAAAcAAYJvRU4swAaAQAYAAQJBRV6JADxAAABLgAECggJIAAKAO4eAA==.Wynain:BAAALgADCgUJBQAAAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAABLgAECn8UAAILAAYJ+QksWwDlAAALAAYJ+QksWwDlAAAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yapparz:BAAALgADCgYJBgAAAA==.Yappor:BAABLgAECn8YAAIcAAgJuxQxWQDBAQAcAAgJuxQxWQDBAQAAAA==.',
Ye='Yekteniya:BAAALgAFFAEJAQAAAA==.Yerrback:BAAALgAECgUJBwAAAA==.',
Yi='Yibbers:BAAALgADCgIJAgAAAA==.Yiimmyy:BAAALgAECgMJBAAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yunô:BAAALgAECgEJAQAAAA==.Yur:BAAALgADCgcJDAABLgAECgkJIQAGAGQiAA==.Yutch:BAAALgAECgYJEAAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAABLgAECn8bAAMKAAcJaAy5FQD8AAAKAAcJaAy5FQD8AAAJAAIJrAM1LAE8AAAAAA==.Zakkydrakky:BAABLgAECn8iAAMoAAkJIQ32FwBSAQAoAAgJLg32FwBSAQAQAAYJPggxWADSAAAAAA==.Zani:BAAALgAECgIJAwAAAA==.Zarashara:BAABLgAECn8lAAMhAAgJFBQ6LABYAQAhAAcJERY6LABYAQAgAAgJcQiePAAOAQAAAA==.',
Ze='Zeddoc:BAEALgAECgMJAwABLgAECgQJCQAFAAAAAA==.Zedward:BAEALgAECgQJCQAAAA==.Zelta:BAAALgADCgkJEwAAAA==.Zenfist:BAAALgADCgIJAgAAAA==.Zeraxhul:BAAALgAECgEJAgAAAA==.Zergio:BAAALgADCgkJCQAAAA==.Zerise:BAAALgAECgUJCwAAAA==.',
Zo='Zolidus:BAAALgAECgYJEAAAAA==.Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAFFAMJBAAFAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8jAAIcAAkJKBL2aQCbAQAcAAkJKBL2aQCbAQAAAA==.Zun:BAAALgAECggJDQAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Çj']='Çj:BAAALgAECgEJAQAAAA==.',
['Èz']='Èzili:BAAALgAECgYJCwAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMTAAgJRRRZVgDuAQATAAgJ/BJZVgDuAQAlAAUJxAzMIwCxAAAAAA==.',
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
