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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Unknown-Unknown','DemonHunter-Devourer','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Warrior-Arms','Mage-Frost','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Blood','Warrior-Fury','Mage-Arcane','DemonHunter-Havoc','Shaman-Elemental','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Druid-Balance','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Druid-Guardian','Druid-Feral','Rogue-Outlaw','Monk-Brewmaster','Warrior-Protection',}
local provider = {region='US',realm='Icecrown',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaronstorm:BAAANQAECgUICgAAAA==.',
Ac='Acesaber:BAAANQABCgIJBAAAAA==.Ackward:BAABNQAECoEaAAIBAAgKEB8uGgCvAgABAAgKEB8uGgCvAgAAAA==.Ackwarder:BAAANQAECgYIEAABNQAECggIGgABABAfAA==.Acrylia:BAAANQAECgIIAgAAAA==.',
Ae='Aeryx:BAABNQAECoEkAAICAAkK8BUXOAA4AgACAAkK8BUXOAA4AgAAAA==.',
Ah='Ahridne:BAAANQAECgUICgAAAA==.Ahsôka:BAAANQAECgQIDQAAAA==.',
Ak='Akisa:BAAANQADCgIIAgAAAA==.',
Al='Alagorn:BAAANQADCggJDQAAAA==.Alamage:BAAANQADCgUIBQAAAA==.Alinael:BAAANQADCggIEgAAAA==.Alisterr:BAAANQAECgQJBAAAAA==.Alistra:BAAANQADCggIDQAAAA==.Alrera:BAAANQAECgQIBAAAAA==.Alynaa:BAAANQAECgUIDAAAAA==.',
Am='Amadixiechic:BAAANQADCggIDAAAAA==.Amafrey:BAABNQAECoEdAAMDAAgKTwuwXAC2AQADAAgKTwuwXAC2AQAEAAMK4RJvQACdAAAAAA==.Ambush:BAAANQADCgUICgAAAA==.Amo:BAAANQAECggIIAAAAQ==.Amocat:BAAANQAECgQIBAABNQAECggIIAAFAAAAAQ==.Amoresto:BAAANQADCgYIBgABNQAECggIIAAFAAAAAQ==.Amoret:BAAANQADCgQIBQABNQAECggIIAAFAAAAAQ==.',
An='Ancestraljr:BAAANQAECgYIEAAAAA==.Andaa:BAAANQADCgUIBQAAAA==.Andalocke:BAABNQAECoEaAAIGAAgKzRbIGwBBAgAGAAgKzRbIGwBBAgAAAA==.Andraka:BAAANQAECgEIAQAAAA==.Andrew:BAAANQADCgQIBAAAAA==.Anitapotion:BAAANQADCgUIBQAAAA==.Annalucia:BAAANQADCgEIAQAAAA==.Annboleyn:BAAANQAECgEIAQAAAA==.',
Ap='Aporkchop:BAAANQAECgEIAgAAAA==.',
Ar='Arabelle:BAABNQAECoEZAAIHAAYK4A1dMQAnAQAHAAYK4A1dMQAnAQAAAA==.Arcatraz:BAAANQADCgEIAQABNQAECgIIBAAFAAAAAA==.Archurroso:BAAANQADCgUJBQAAAA==.Ares:BAAANQADCgcJEQAAAA==.Ariens:BAABNQAECoEYAAMIAAgKQRQtVwAbAgAIAAcK8xYtVwAbAgAJAAIKpgaAYABVAAAAAA==.Arlaeya:BAAANQAECgEIAQAAAA==.Arocyra:BAAANQABCgYIDAAAAA==.Artemislux:BAABNQAECoEdAAMJAAkKWRoBGgBQAgAJAAgKaRsBGgBQAgAIAAMK3xfG2ADiAAAAAA==.Aránda:BAAANQAECgMIAwAAAA==.',
As='Astelle:BAABNQAECoEbAAIKAAcKFxkGIwANAgAKAAcKFxkGIwANAgAAAA==.',
At='Atagos:BAABNQAECoEZAAILAAcKQRRSggDAAQALAAcKQRRSggDAAQAAAA==.Athanor:BAAANQAECgQIBAABNQAECgcIEwAFAAAAAA==.Atonementism:BAAANQAECgUIEAABNQAECgIIAQAFAAAAAA==.',
Au='Aurawa:BAAANQAECgIIAgAAAA==.Aurus:BAAANQAECgEIAQAAAA==.Austin:BAAANQAECggIEgAAAA==.Autumnn:BAAANQADCgUIBQAAAA==.',
Av='Avannia:BAAANQADCgcICwAAAA==.Avaren:BAABNQAECoEeAAIMAAkK6CCDAQBQAwAMAAkK6CCDAQBQAwABNQAECgkJMAANALUkAA==.Avarens:BAAANQAECgYICgABNQAECgkJMAANALUkAA==.Avawen:BAABNQAECoEwAAQNAAkKtSQSAgC5AwANAAkKHyQSAgC5AwAOAAgKBh81AgDdAgAPAAEKeBA/XwA3AAAAAA==.Averyg:BAAANQADCgYJFAAAAA==.',
Aw='Awhbeans:BAEANQAECgYIEQAAAA==.',
Ax='Axtafal:BAAANQAECgYIEQAAAA==.',
Ay='Ayla:BAAANQADCgcIDgAAAA==.',
['Aá']='Aáronstorm:BAAANQADCggICgABNQAECgUICgAFAAAAAA==.',
Ba='Babaganouj:BAAANQADCgYIFgABNQADCggIJwAFAAAAAA==.Baineblood:BAAANQAECggIEgAAAA==.Bainelock:BAAANQAECgIIAgAAAA==.Bandledin:BAAANQAECgUIDgAAAA==.Barelilus:BAAANQAECgMJAwAAAA==.Barthus:BAAANQAECgIIAgABNQAECgUICgAFAAAAAA==.Baseballman:BAAANQADCggJDgABNQAECgkJMAANALUkAA==.Bassproshops:BAACNQAFFIEMAAIIAAUKTBhlBAC7AQAIAAUKTBhlBAC7AQA1AAQKgSwAAwgACQrEIpcRADQDAAgACQqLIZcRADQDAAkABQrRHi8nAMcBAAAA.Baulder:BAAANQAECgIIAgAAAA==.',
Be='Bear:BAAANQADCgEIAQABNQAFFAYIGQAQAEYmAA==.Belmyridon:BAAANQADCgcICgAAAA==.Belzebozz:BAAANQADCgMIAwAAAA==.Bendecido:BAAANQADCggIDQAAAA==.',
Bf='Bfc:BAAANQADCgUIBQAAAA==.',
Bi='Biaxident:BAAANQAECgUIDwAAAA==.Bigboy:BAAANQAECgYICAAAAA==.Bigjoe:BAAANQAECgUJBQAAAA==.Birdyy:BAAANQADCgYICgABNQADCggJDgAFAAAAAA==.',
Bj='Bjorne:BAABNQAECoEsAAIRAAgKIw4eCgDeAQARAAgKIw4eCgDeAQAAAA==.',
Bl='Blammo:BAAANQADCgUIBQAAAA==.Blastoise:BAAANQAECgEIAgAAAA==.Blazter:BAAANQAECgcIEgAAAA==.Bleo:BAAANQAECgEIAQAAAA==.Blueberryjam:BAAANQADCggIDgABNQAECggIGQASAJIIAA==.Blututh:BAABNQAECoEXAAITAAgKeg6QLADmAQATAAgKeg6QLADmAQAAAA==.Blïght:BAAANQADCggIHAAAAA==.',
Bm='Bmjr:BAABNQAECoEfAAILAAkKqyMgCQCaAwALAAkKqyMgCQCaAwAAAA==.',
Bo='Bodhran:BAABNQAECoEhAAIUAAkK2hIOOABPAgAUAAkK2hIOOABPAgAAAA==.Bombadill:BAAANQAECgEJAQAAAA==.Bonewings:BAAANQADCggICQAAAA==.Boombang:BAAANQAECgEIAQAAAA==.',
Br='Breezerk:BAABNQAECoEhAAILAAkKXRzoJwDxAgALAAkKXRzoJwDxAgAAAA==.Brill:BAAANQABCgIIAgAAAA==.Brudrushah:BAAANQAECgQIBAABNQAECgUIDgAFAAAAAA==.',
Bu='Bubblebetuna:BAAANQABCgIIAgABNQABCgYIBgAFAAAAAA==.Buggerella:BAAANQAECgIIAgAAAA==.Bullithead:BAAANQADCggICQAAAA==.Bulrog:BAABNQAECoEeAAIVAAkKchn8EgB7AgAVAAkKchn8EgB7AgAAAA==.Bumpey:BAAANQADCgUICQABNQADCggIDAAFAAAAAA==.Bus:BAACNQAFFIEOAAIQAAYKNyEAAgBKAgAQAAYKNyEAAgBKAgA1AAQKgRgAAhAACQq0JMQDAKUDABAACQq0JMQDAKUDAAAA.Bushlite:BAABNQAECoEWAAIWAAgKhRHtfgDIAQAWAAgKhRHtfgDIAQAAAA==.',
By='Byni:BAAANQAECgUICwAAAA==.',
['Bá']='Bádabing:BAAANQABCgQIBgAAAA==.',
Ca='Calorenn:BAAANQADCgYICgABNQAECgYIEgAFAAAAAA==.Caluu:BAABNQAECoEpAAMWAAkKUiASJgD3AgAWAAkKfxwSJgD3AgAEAAIKDhlYQwCMAAAAAA==.Cankles:BAAANQAECggIDQAAAA==.Canolope:BAAANQADCgYIBgABNQAECgcJDgAFAAAAAA==.Cantcant:BAAANQAECgQIBAABNQAECgkJMAANALUkAA==.Catfood:BAABNQAECoEUAAQGAAgKtx3ZHwATAgAGAAcK4xrZHwATAgATAAQK1B18SwD7AAAXAAEKVQvxJgArAAAAAA==.Cattibriee:BAAANQADCgMJAwAAAA==.',
Ce='Cece:BAAANQAECgQIBAABNQAECgUICgAFAAAAAA==.Celedhring:BAABNQAECoEsAAIWAAgKjRLKaAAHAgAWAAgKjRLKaAAHAgAAAA==.',
Ch='Chainsaww:BAAANQADCgMIAwAAAA==.Chaktaw:BAABNQAECoEbAAMOAAcKQxoZBQAoAgAOAAcKQxoZBQAoAgAPAAEKqxLZXAA9AAAAAA==.Chatubaholy:BAAANQAECgQIBQAAAA==.Chayito:BAABNQAECoEmAAMGAAkK9hlxEwCiAgAGAAkK9hlxEwCiAgAXAAUKUQwUFAAEAQAAAA==.Cheezi:BAAANQAECgQIBAAAAA==.Chickenism:BAECNQAFFIEhAAIYAAgK8B5bAAATAwAYAAgK8B5bAAATAwA1AAQKgS8AAhgACQrbJj8AAAYEABgACQrbJj8AAAYEAAAA.Chiknsmoothi:BAAANQADCgYICwAAAA==.Chirpa:BAAANQADCgMIAwAAAA==.Chiwallow:BAAANQAECgQIBAAAAA==.Chloe:BAAANQAECgUIDgAAAA==.Chowtime:BAABNQAECoEfAAISAAgKwRYbhAA6AgASAAgKwRYbhAA6AgAAAA==.Chromium:BAAANQAECgcIEwAAAA==.Chrysanthia:BAAANQADCgEIAQAAAA==.',
Ci='Cinderstorm:BAAANQADCgYICQAAAA==.Cirilla:BAAANQABCgIIAgAAAA==.Citronia:BAAANQAECgYICQAAAA==.',
Cl='Clamps:BAABNQAECoEWAAMCAAgK8iC+JwCJAgACAAgK8iC+JwCJAgAZAAEK/AVPLAAzAAAAAA==.Clandmage:BAAANQAECgYIBgAAAA==.Clandon:BAACNQAFFIElAAIOAAgKPx4HAAA8AwAOAAgKPx4HAAA8AwA1AAQKgS0AAg4ACQrYJgoAAAwEAA4ACQrYJgoAAAwEAAAA.Claxton:BAABNQAECoEkAAMRAAgK7BaYBgBKAgARAAgK7BaYBgBKAgALAAYKfQm1sQA0AQAAAA==.Clomari:BAAANQAECgcIDgAAAA==.Clynlyn:BAAANQAECgMIAwAAAA==.',
Co='Cole:BAAANQADCgcIBwAAAA==.Commietotem:BAAANQAECgIIBAAAAA==.Concepts:BAABNQAECoEeAAMWAAgK9hojQQCHAgAWAAgK9hojQQCHAgADAAMKJg/cvACyAAAAAA==.Conjax:BAAANQAECgEIAQAAAA==.Costcomember:BAAANQADCgcICQAAAA==.Coyn:BAAANQADCgQIBAABNQADCgUIBQAFAAAAAA==.',
Cr='Crashout:BAAANQAECgEIAQAAAA==.Crison:BAAANQADCgcIDQABNQAECgUIBwAFAAAAAA==.Cron:BAAANQADCgcIBwAAAA==.Croneos:BAAANQAECgQIBQAAAA==.Cross:BAABNQAECoEiAAMEAAgKfRcGFQAIAgAEAAgKfRcGFQAIAgAWAAIKrRAdJAFnAAAAAA==.Cryssalis:BAAANQADCgEIAQAAAA==.',
Cu='Cudz:BAAANQAECgUICgAAAA==.Curl:BAAANQAECgUICQAAAA==.',
Cy='Cyn:BAAANQADCgEIAQAAAA==.Cytanous:BAAANQADCgYIEQAAAA==.',
Da='Daddydeath:BAABNQAECoEXAAIPAAcKXBPeIwDCAQAPAAcKXBPeIwDCAQAAAA==.Dadrex:BAAANQADCgMIAwAAAA==.Daesyn:BAAANQADCgEIAQAAAA==.Dagonfive:BAAANQAECgYICwAAAA==.Dahrla:BAAANQAECgYIDAAAAA==.Daisyann:BAAANQAECgYIEwAAAA==.Dalebeanhrdt:BAAANQADCggIDAAAAA==.Dallasx:BAAANQADCgUIBQAAAA==.Dalmarr:BAAANQAECgQIBAAAAA==.Dancouga:BAABNQAECoEZAAIaAAcKjQs8IAClAQAaAAcKjQs8IAClAQAAAA==.Dantallon:BAEANQAECgIIBQABNQAECgYIFQAWAI0hAA==.Darkdarius:BAAANQADCgUICQAAAA==.Darthmaulus:BAAANQAECgUJCAABNQAECggIGAASAB4KAA==.Daruncic:BAAANQAECgUIDgAAAA==.Dave:BAABNQAECoEZAAISAAgKkggrvgC4AQASAAgKkggrvgC4AQAAAA==.Dawnchatters:BAAANQADCgQIBAAAAA==.Dawntodusk:BAAANQADCgYIBgAAAA==.Daymia:BAAANQAECgYIEQAAAA==.Dazknight:BAABNQAECoEXAAQbAAcKTxhUNgCRAQAbAAYKchhUNgCRAQAQAAIKXg/OjwB9AAABAAEK5AXpugAnAAAAAA==.Dazshaman:BAAANQADCggIFAABNQAECgcIFwAbAE8YAA==.',
De='Deadion:BAAANQAECgYIEgAAAQ==.Deadpaly:BAAANQADCgMIAwABNQAECgYIEgAFAAAAAQ==.Deadspinwin:BAAANQADCgIIAgABNQAECgYIEgAFAAAAAQ==.Dearmage:BAABNQAECoEXAAISAAgKXBOdjwAfAgASAAgKXBOdjwAfAgAAAA==.Deathgripz:BAAANQADCggIGwAAAA==.Deathlockdes:BAAANQAECgEIAQAAAA==.Decormei:BAAANQAECgUIEwAAAA==.Dedman:BAAANQABCgQIAwAAAA==.Deltatoast:BAAANQADCgQICAAAAA==.Delusionz:BAAANQAECgQIBAABNQAECgUICgAFAAAAAA==.Demera:BAAANQAECgYIDgAAAA==.Demolack:BAAANQADCgIIBwAAAA==.Destheleye:BAAANQADCgMIAwAAAA==.Dethnyte:BAAANQAECgUJBwAAAA==.Deyjavaknadi:BAAANQADCgUIBQAAAA==.',
Di='Diaf:BAABNQAECoEdAAISAAcKZBGlygCfAQASAAcKZBGlygCfAQAAAA==.Diniwen:BAABNQAECoEZAAISAAgKCB5tTADDAgASAAgKCB5tTADDAgAAAA==.Dirienna:BAAANQABCgIIAgAAAA==.Dirtbikes:BAAANQAECgcICwAAAA==.Discordmod:BAAANQAECgYICwAAAA==.Dithia:BAAANQAECgcIEQAAAA==.Divided:BAAANQAECgcICgAAAA==.Division:BAABNQAECoEXAAIZAAkKPCTgAQCKAwAZAAkKPCTgAQCKAwAAAA==.',
Dj='Djparrot:BAAANQAECgYIDwAAAA==.',
Do='Domrï:BAAANQAECgcICwAAAA==.Donkayslayer:BAAANQAECgYIEQAAAA==.Donlock:BAAANQAECgUIBQAAAA==.Doohoo:BAAANQAECgcIEwAAAA==.Dordrel:BAAANQADCgEIAQAAAA==.Douchekanu:BAAANQADCggIDgAAAA==.Downpour:BAAANQAECgcICwAAAA==.',
Dr='Dracdad:BAAANQADCgEIAQABNQAECgMIAwAFAAAAAA==.Draevon:BAAANQADCgQICAABNQAECgUIDAAFAAAAAA==.Dragathor:BAAANQADCggICAAAAA==.Dragondnutz:BAAANQAECgIIAgABNQAECgYICgAFAAAAAA==.Dragoness:BAAANQADCgQIBAAAAA==.Dragonflight:BAAANQAECgcIEwAAAA==.Drakloak:BAACNQAFFIEZAAMcAAgKgB35AAAuAgAcAAYKoR35AAAuAgAdAAQK3BbTAgB9AQA1AAQKgSMAAxwACQpvJRUDAGADABwACQqzJBUDAGADAB0AAwr1JYYLAE0BAAAA.Drclaw:BAAANQADCgQIBAABNQADCggICAAFAAAAAA==.Drench:BAAANQAECgYIEQAAAA==.',
Du='Duckdodger:BAAANQADCgIIAgAAAA==.Durota:BAABNQAECoEcAAIIAAcKKgWzogBXAQAIAAcKKgWzogBXAQAAAA==.',
Dv='Dv:BAAANQADCggJDgAAAA==.',
Dw='Dwarftoss:BAABNQAECoEeAAIUAAgK1xekNQBcAgAUAAgK1xekNQBcAgAAAA==.',
Dz='Dzasterpiece:BAACNQAFFIENAAMbAAcKFReiAABWAgAbAAcKFReiAABWAgAQAAEKGhb7IABAAAA1AAQKgTgAAxsACQpeJR0BANcDABsACQpeJR0BANcDABAAAQoZDy2tADAAAAAA.',
['Dà']='Dàmnàtion:BAAANQADCgEIAQAAAA==.',
['Dä']='Däemarcus:BAAANQAECgYIDwAAAA==.',
['Dò']='Dòyòùnèèd:BAAANQADCgMIBAAAAA==.',
Ec='Ectyxx:BAABNQAECoEhAAISAAkKKyDFMgAJAwASAAkKKyDFMgAJAwAAAA==.',
Ed='Edris:BAAANQAECgYICwAAAA==.',
Ef='Effört:BAAANQADCggJGQAAAA==.',
Ei='Eightlug:BAAANQAECgEIAQAAAA==.',
El='Elareis:BAAANQADCgUIDwAAAA==.Elebits:BAAANQADCgIIBAABNQAFFAYICgAIANkOAA==.Eluned:BAAANQAECgcIEgAAAA==.Elwynn:BAAANQAECgcIHAAAAQ==.Elycia:BAAANQADCgYICwAAAA==.',
Em='Emosmaug:BAACNQAFFIEHAAIGAAMKTRgVCAAMAQAGAAMKTRgVCAAMAQA1AAQKgRwAAgYACQo+H/EMAPYCAAYACQo+H/EMAPYCAAAA.',
En='Enkistral:BAAANQAECgMIAwABNQAFFAMIBwAYALIPAA==.Envi:BAAANQAECgMIBAAAAA==.',
Er='Eretar:BAAANQAECgEIAQAAAA==.Erotaph:BAAANQAECgUIDgAAAA==.',
Eu='Euron:BAAANQAECgUIDAAAAA==.',
Ev='Evach:BAABNQAECoEjAAMJAAkKhiJ6FQCFAgAJAAgKziJ6FQCFAgAIAAIKrRu/9gCCAAAAAA==.Everblight:BAAANQADCgYICwAAAA==.',
Fa='Facex:BAAANQADCggIDgAAAA==.Faelor:BAAANQADCggIGwAAAA==.Faet:BAAANQAECgYIEwAAAA==.Faeyt:BAAANQAECgYIEgAAAA==.Fatkokmage:BAAANQADCggIDAAAAA==.',
Fc='Fcawfng:BAAANQADCgUIBwAAAA==.',
Fe='Felakai:BAAANQADCggIHQAAAA==.',
Fi='Fidgetspinna:BAAANQADCgIIAgAAAA==.Finaljudgmnt:BAAANQADCgIIAgABNQAECggIGQANAGQPAA==.Finesthour:BAACNQAFFIEdAAMBAAgKWyUCAABRAwABAAgKWyUCAABRAwAQAAEKmxSkIgA6AAA1AAQKgSwAAgEACQrRJq4BANMDAAEACQrRJq4BANMDAAAA.Fingerlicker:BAAANQADCgcIDQAAAA==.Finnaburnya:BAAANQADCgYIBwAAAA==.Finnacreep:BAAANQADCgcIBwAAAA==.Firepower:BAAANQABCgIIAgAAAA==.Fitzwilliam:BAAANQAECgcIEQAAAA==.Fives:BAAANQAECgYIDQAAAA==.',
Fj='Fjordchi:BAAANQAECgYIEQAAAA==.',
Fl='Fluxy:BAAANQADCgYIBgAAAA==.',
Fo='Fonzie:BAABNQAECoEXAAIBAAcKPBClUgBgAQABAAcKPBClUgBgAQAAAA==.Foozykinz:BAAANQADCgMIAwAAAA==.Forlorn:BAAANQAECgUIDQAAAA==.Fortsmite:BAAANQADCgUICQAAAA==.Foxicious:BAABNQAECoEWAAIPAAgKKxB4HwDzAQAPAAgKKxB4HwDzAQAAAA==.Foxjaw:BAAANQADCgIIAgAAAA==.Foxpaw:BAABNQAECoEvAAIIAAgKCAvgYQD9AQAIAAgKCAvgYQD9AQAAAA==.',
Fr='Fraggle:BAEANQAECgIIAgAAAA==.Frankoc:BAAANQADCgMIAwAAAA==.Freeza:BAAANQADCgQIBAAAAA==.Freshlock:BAABNQAECoEhAAMeAAgK3iPCEAAmAwAeAAgK3iPCEAAmAwAfAAEKmx8dYQBJAAAAAA==.Freyr:BAAANQAFFAEIAQAAAA==.Frostbitë:BAAANQADCgEIAQAAAA==.Frostfires:BAABNQAECoEZAAISAAcKJhoHkgAZAgASAAcKJhoHkgAZAgAAAA==.Frostlawlz:BAAANQADCgUICQAAAA==.',
Fu='Fubashi:BAABNQAECoEpAAIHAAkKdCOBAgCSAwAHAAkKdCOBAgCSAwABNQAECgUICgAFAAAAAA==.Furritoo:BAAANQAECgcJDgAAAA==.Fuzzie:BAAANQAECgIIAgAAAA==.',
Fy='Fyneshi:BAAANQADCgUIBQAAAA==.',
Ga='Gachiwl:BAACNQAFFIEgAAQeAAgKWhujAgAVAgAeAAYKOBqjAgAVAgAgAAMKnBm5AAA+AQAfAAIKPCZaAwDUAAA1AAQKgS0ABCAACQqiJlYAALADACAACQpyJFYAALADAB8ACAqYJfoBADsDAB4ABgoqJlg3AHICAAAA.Galirana:BAAANQAECgcIDwAAAA==.Gamergoo:BAAANQAECgcJEAAAAA==.Gampshwago:BAABNQAECoEcAAMcAAkKVyEiBgAGAwAcAAgKVyEiBgAGAwAhAAkKfQ0kFwAQAgABNQAECgMIBAAFAAAAAA==.Garion:BAAANQADCgQIBAAAAA==.Garkk:BAAANQAECgYIDgAAAA==.Garronan:BAACNQAFFIEkAAMJAAgKICJ3AAD1AgAJAAgK+B13AAD1AgAIAAEKGSMqHgBpAAA1AAQKgSwAAwkACQoyJswGAE4DAAkACAoiJswGAE4DAAgAAgpsJYXrAKgAAAAA.',
Ge='Geary:BAAANQAECgQIBgABNQAECgYICwAFAAAAAA==.Gelina:BAAANQAECgcIEAAAAA==.Getfookd:BAAANQADCgYIBgAAAA==.Geveesa:BAAANQAECgYIEQAAAA==.',
Gi='Gibdk:BAAANQAECgMIAwABNQAECggIHAAfABkaAA==.Gibletss:BAABNQAECoEcAAQfAAgKGRqWKQAYAQAeAAYKKhgVaADPAQAfAAQKoxSWKQAYAQAgAAEK4CEnHABjAAAAAA==.',
Gl='Glaivedigger:BAABNQAECoEbAAIGAAcK6BbsIwDtAQAGAAcK6BbsIwDtAQAAAA==.Glollan:BAAANQAECgEIAQAAAA==.',
Go='Golda:BAABNQAECoEnAAIVAAcKEA3lKABvAQAVAAcKEA3lKABvAQAAAA==.Goonerbait:BAAANQAECgQJBQAAAA==.Goragon:BAAANQAECgYIDAAAAA==.Gorkgork:BAAANQAECgQIBAAAAA==.',
Gr='Grass:BAAANQADCgcICgAAAA==.Grcorolla:BAABNQAECoEmAAILAAkKmiXfBADCAwALAAkKmiXfBADCAwAAAA==.Grindder:BAAANQAECgMIBQAAAA==.Grippers:BAAANQADCgYIBgAAAA==.Groshnok:BAAANQAECgYIEAAAAA==.Grunky:BAAANQAECggIEwAAAA==.Grunkyvoke:BAAANQAECgIIAgABNQAECggIEwAFAAAAAA==.',
Gu='Guanyin:BAAANQADCgUIBQAAAA==.Gustobooms:BAAANQAECgMIAwAAAA==.',
Gw='Gwantanamata:BAAANQADCggICAAAAA==.',
['Gì']='Gìrthquake:BAABNQAECoEjAAIUAAkKjyKqCwByAwAUAAkKjyKqCwByAwAAAA==.',
Ha='Haiayla:BAAANQADCgcIDAAAAA==.Haleybug:BAAANQADCgUIBwAAAA==.Halyax:BAAANQAECgQICAAAAA==.Hammerslol:BAAANQADCggICAAAAA==.Hamoron:BAAANQADCgYIBgAAAA==.',
Hd='Hdog:BAAANQAECgIIAgAAAA==.',
He='Heisenbergz:BAAANQADCgMIBQAAAA==.Helicopter:BAAANQADCggICAABNQAECgIIAwAFAAAAAA==.Henter:BAAANQADCgUIBQAAAA==.Herm:BAAANQAECgQIBwAAAA==.Hesel:BAAANQAECgcICwAAAA==.',
Hi='Hihowareya:BAACNQAFFIEHAAIGAAUK4SBuAwDnAQAGAAUK4SBuAwDnAQA1AAQKgSwAAwYACQq4JmcAAPoDAAYACQq4JmcAAPoDABMAAQp2HUdqAFYAAAAA.Hildegar:BAAANQAECgUIDwAAAA==.',
Ho='Hokiette:BAAANQAECgYIDwAAAA==.Holdmydeeps:BAAANQAECgYIDgAAAA==.Holybabs:BAAANQADCgIIAgAAAA==.Horehronie:BAAANQADCggIHwAAAA==.Hosebaggins:BAAANQADCgcIDQABNQAECgUIDgAFAAAAAA==.How:BAAANQADCgUIBQAAAA==.',
Hu='Hubbles:BAACNQAFFIEgAAICAAgKDhWCAADHAgACAAgKDhWCAADHAgA1AAQKgSwAAgIACQqGJOQEAIoDAAIACQqGJOQEAIoDAAAA.Hububbles:BAAANQAECgQICQABNQAFFAgIIAACAA4VAA==.',
Hy='Hybla:BAAANQADCgYIBgAAAA==.Hylikus:BAAANQAECgcIEQAAAA==.',
['Hë']='Hëlen:BAAANQADCgYICgAAAA==.Hëllräisër:BAAANQADCgUIBQAAAA==.',
['Hô']='Hôlystôrm:BAAANQAECgUIDAAAAA==.',
Ic='Icesaber:BAAANQAECgQIDAAAAA==.Icevili:BAAANQAECgcIEAAAAA==.Ichigonyne:BAAANQADCgcJFgAAAA==.Iciala:BAAANQADCgMIBAAAAA==.',
Ig='Iggar:BAAANQAECgMIAwAAAA==.Igotu:BAAANQAECgIIBAAAAA==.Igris:BAAANQAECgQIBgAAAA==.',
Im='Imira:BAAANQADCgYIDAABNQAECgUIDAAFAAAAAA==.Impster:BAAANQADCggICAAAAA==.Impushpop:BAAANQAECgQIBgAAAA==.Imsokool:BAAANQADCgcIEgAAAA==.Imsure:BAAANQAECgQIEAAAAA==.',
In='Indigos:BAAANQAECgIIAgAAAA==.Ineedhelp:BAAANQAECggIAQAAAA==.',
Ir='Irasyn:BAAANQADCgYICwAAAA==.Ironpork:BAAANQADCgUIBQAAAA==.',
Is='Isam:BAAANQAECgYIDwAAAA==.',
Ja='Jackietran:BAAANQADCggIDwAAAA==.Jadefire:BAABNQAECoEgAAIVAAgKSh3FEgB+AgAVAAgKSh3FEgB+AgAAAA==.Jaedemon:BAABNQAECoEtAAITAAkKJyA9CgA4AwATAAkKJyA9CgA4AwAAAA==.Jakuta:BAAANQAECgUICQAAAA==.Jawbreaker:BAAANQABCgMIAgAAAA==.Jaysön:BAAANQADCgcIDwAAAA==.',
Je='Jebuku:BAAANQAECgUICgAAAA==.Jenkeez:BAAANQABCggICAAAAA==.Jestius:BAAANQAECgEIAQAAAA==.Jetpakmonkey:BAAANQADCgcIBwAAAA==.Jeudi:BAAANQADCgcIEgAAAA==.',
Ji='Jinxblue:BAAANQAECgcIDgAAAA==.Jiroyan:BAAANQAECgUICQAAAA==.',
Jo='Joralö:BAAANQAECgYICwAAAA==.',
Jt='Jtvikiing:BAAANQAECgEIAgABNQAECggIEwAYAMIZAA==.',
Ju='Jubilee:BAABNQAECoEfAAMbAAcKiBPXNACbAQAbAAcK2BLXNACbAQABAAYKfAwyZQATAQAAAA==.Jumpies:BAAANQAECgUIDgAAAA==.Jupiturr:BAAANQAECgYIEAAAAA==.Justian:BAAANQAECgEIAQAAAA==.Juunbroh:BAABNQAECoEyAAIDAAgKCRj5MwBZAgADAAgKCRj5MwBZAgAAAA==.',
['Jé']='Jénova:BAAANQAECgEIAQAAAA==.',
['Jö']='Jörd:BAAANQAECgQIBgAAAA==.',
Ka='Kaa:BAAANQADCgUIBQABNQAECgkJJAAiACkeAA==.Kaarin:BAAANQADCgcIBwABNQAECggIGAASAB4KAA==.Kabillabob:BAAANQADCgQIBAAAAA==.Kadowe:BAABNQAECoEXAAISAAgKpx7+TQC/AgASAAgKpx7+TQC/AgAAAA==.Kaiyla:BAAANQADCgcICQAAAA==.Kalacrity:BAAANQADCgYIBgABNQAECgkJGwAZAHcaAA==.Kaladinn:BAAANQAECgYIDwAAAA==.Kalintene:BAAANQADCgIIAgABNQAECgkJIAAjAEseAA==.Kalpanda:BAAANQAECgQIBAABNQAECgkJGwAZAHcaAA==.Kaonashi:BAAANQADCgcIBwAAAA==.Kargan:BAAANQAECgIIAwABNQAECgYIEQAFAAAAAA==.Karma:BAAANQADCgcICwAAAA==.Karthas:BAAANQAECgYIEQAAAA==.Kassian:BAAANQAECgUIDgAAAA==.Kastbeel:BAAANQADCggICAAAAA==.Kayhana:BAAANQAECgEIAQAAAA==.',
Ke='Keillea:BAAANQADCgcIDgABNQAFFAIIBAAFAAAAAA==.Keir:BAAANQAECgYIEQAAAA==.Kelsey:BAAANQADCgYICQABNQAECgYIEwAFAAAAAA==.Kenny:BAAANQAECgUIDwAAAA==.Kevindurand:BAAANQABCgQIBAAAAA==.Keyanor:BAAANQAECgYIEQAAAA==.',
Kh='Khaeltharion:BAAANQAECgYIDwAAAA==.Khalan:BAABNQAECoEZAAIjAAgK4hTQCgAbAgAjAAgK4hTQCgAbAgAAAA==.Khavatari:BAABNQAECoEaAAILAAgKIBayYwAaAgALAAgKIBayYwAaAgAAAA==.Khazidhea:BAAANQADCgQICgABNQAECgUIDQAFAAAAAA==.Khazmyk:BAAANQADCgIIAgABNQAECgUIDQAFAAAAAA==.Khazrael:BAAANQAECgUIDQAAAA==.Khazriel:BAAANQADCgcJEgABNQAECgUIDQAFAAAAAA==.',
Ki='Killerpin:BAAANQAECgQICgAAAA==.Killig:BAAANQABCgIIAgAAAA==.Kilmanov:BAAANQAECggIBgAAAA==.Kitmeup:BAACNQAFFIEUAAISAAcKlRYaAwBfAgASAAcKlRYaAwBfAgA1AAQKgRwAAhIACQq3Jb8TAHUDABIACQq3Jb8TAHUDAAAA.',
Ko='Kookiez:BAABNQAECoEdAAIeAAgKxQpRbADCAQAeAAgKxQpRbADCAQAAAA==.Korbane:BAAANQADCgYICwAAAA==.Kordormu:BAAANQADCgMIAwAAAA==.Korrupshun:BAAANQAECgcJDgAAAA==.Korvian:BAAANQAECgYIEwAAAA==.Kozzyy:BAAANQADCgIJAgAAAA==.',
Kr='Kraatose:BAAANQADCgUIBwABNQAECgMIBQAFAAAAAA==.Kraizy:BAABNQAECoEXAAINAAkKWxi/IwCkAgANAAkKWxi/IwCkAgABNQAECgkJLQASANEbAA==.Kro:BAAANQADCgYIDQAAAA==.Krymsy:BAAANQAECgYICwAAAA==.',
Ky='Kynigós:BAABNQAECoEcAAIIAAYKaSAnUwAnAgAIAAYKaSAnUwAnAgAAAA==.',
Kz='Kzerg:BAAANQAECgQIBwAAAA==.',
La='Laastira:BAAANQADCgQIBAABNQAECgIIAgAFAAAAAA==.Labzy:BAAANQADCgQIBAAAAA==.Laestra:BAAANQABCgIIAgAAAA==.Lalinthor:BAAANQADCgMIAwAAAA==.Lamìà:BAAANQADCgcJBwABNQAECggIGQALAMEZAA==.Lavendér:BAABNQAECoEbAAIeAAkK7hSUMwCAAgAeAAkK7hSUMwCAAgAAAA==.',
Le='Leerooy:BAAANQADCgIIAgAAAA==.Leobardo:BAAANQADCggIDAAAAA==.',
Li='Lightsfury:BAAANQADCgEIAQABNQAECgMIAwAFAAAAAA==.Lihp:BAAANQAECgUICQAAAA==.Liljj:BAAANQAECgIIAgAAAA==.Limmy:BAAANQADCgMJAwAAAA==.Linndara:BAAANQAECgIIAgAAAA==.Linting:BAABNQAECoEZAAMNAAgKZA9eUQDXAQANAAgKZA9eUQDXAQAPAAEKxQmZaQAmAAAAAA==.Lithsong:BAABNQAECoEoAAMQAAgKUiPhDgATAwAQAAgKUiPhDgATAwABAAIKSgKipgBCAAAAAA==.',
Lo='Lockthor:BAABNQAECoEbAAIeAAgKhhDxWgD4AQAeAAgKhhDxWgD4AQAAAA==.Lonie:BAAANQAECgYIEQAAAA==.Loto:BAAANQAECgMIAwAAAA==.',
Lu='Lucyfury:BAAANQADCgEIAQAAAA==.Luedragosa:BAABNQAECoEmAAQdAAcKvAQgEgC4AAAcAAYKHQPzJQC/AAAdAAUK3gQgEgC4AAAhAAQKeQFLPABhAAAAAA==.Lunademon:BAAANQADCgUIBQAAAA==.Lunadk:BAABNQAECoEYAAIQAAgK3Bj/KABAAgAQAAgK3Bj/KABAAgAAAA==.Lunanecro:BAAANQAECgYIBwAAAA==.Luxmortae:BAAANQABCgIIAgAAAA==.Luxserena:BAAANQAECgEIAQAAAA==.Luxumbrae:BAAANQAECgMIAwAAAA==.',
Ly='Lydie:BAAANQAECgYICwAAAA==.Lynthara:BAAANQADCgYIBgAAAA==.Lysunder:BAAANQAECgYIDwAAAA==.Lythronax:BAABNQAECoEZAAIcAAcK5hqEDgA9AgAcAAcK5hqEDgA9AgAAAA==.',
['Lö']='Löwen:BAAANQAECgUICwAAAA==.',
Ma='Mackro:BAAANQADCggIDgAAAA==.Madblackjack:BAAANQADCgUICQAAAA==.Madmurph:BAAANQADCgUIBQABNQAECgMIAwAFAAAAAA==.Maestro:BAAANQAECgQIBgAAAA==.Magark:BAAANQAECgQIBQAAAA==.Mahanar:BAAANQADCgcICAAAAA==.Maimai:BAAANQADCgcICQAAAA==.Makandcheese:BAAANQADCgIIAQAAAA==.Malice:BAAANQADCggICAAAAA==.Malisenta:BAABNQAECoEmAAMhAAkK8BLLEgBSAgAhAAkK8BLLEgBSAgAdAAYKeQXMDwDhAAAAAA==.Mallboro:BAAANQADCgQIBAAAAA==.Mallis:BAAANQAECgYICwAAAA==.Mardew:BAABNQAECoEZAAILAAgKwRm2TgBeAgALAAgKwRm2TgBeAgAAAA==.Markoramius:BAAANQAECgUIEAAAAA==.Marpew:BAAANQADCgcIDAABNQAECggIGQALAMEZAA==.',
Me='Meatballa:BAAANQAECgYIBgAAAA==.Mehkasingh:BAAANQAECgcIEgAAAA==.Melanotic:BAAANQAECggICAAAAA==.Mellicanisis:BAAANQADCgMIAwAAAA==.Melvalint:BAABNQAECoEYAAISAAgKHgo4twDHAQASAAgKHgo4twDHAQAAAA==.Memademic:BAAANQAECgcIEQAAAA==.Memhuntz:BAAANQADCgUIBQAAAA==.Mendsong:BAAANQAECgUICQAAAA==.Meralonnë:BAAANQAECgMIAwAAAA==.Merigold:BAAANQADCgEIAQAAAA==.Merlins:BAABNQAECoE6AAIeAAgKvBoGMACOAgAeAAgKvBoGMACOAgAAAA==.Messner:BAAANQAECgIIAgAAAA==.',
Mi='Miamiganster:BAABNQAFFIEIAAMKAAUKWBieAgDMAQAKAAUKWBieAgDMAQAaAAMKlQQhCQD1AAABNQAECgMIBAAFAAAAAA==.Milestheevil:BAAANQADCgcICQAAAA==.Mindbullets:BAAANQAECgQIBwAAAA==.Mirah:BAABNQAECoEYAAIHAAYKCxSKKAB0AQAHAAYKCxSKKAB0AQAAAA==.Misclick:BAABNQAECoEaAAISAAkK9yP/CACqAwASAAkK9yP/CACqAwAAAA==.',
Mm='Mmbeans:BAAANQAECgMIAwABNQAECgUIDQAFAAAAAA==.',
Mo='Mochabean:BAAANQAECgUIBQABNQAECggIEgAFAAAAAA==.Mochikat:BAACNQAFFIEdAAIDAAcKvxBHAgBBAgADAAcKvxBHAgBBAgA1AAQKgS0AAgMACQoDI5EFAIwDAAMACQoDI5EFAIwDAAAA.Mogamemnon:BAAANQAECgQIBAAAAA==.Mogriya:BAAANQAECgYIDwAAAA==.Moisttank:BAAANQAECgEIAQAAAA==.Mokt:BAAANQAECgQICgAAAA==.Mollywhop:BAABNQAECoEYAAMCAAcKCBmJQQAPAgACAAcKCBmJQQAPAgAUAAMKJAgtywCVAAAAAA==.Molyneaux:BAAANQAECgUIBwAAAA==.Moonpaw:BAAANQAECgQICwAAAA==.Mooskaroo:BAABNQAECoEfAAIYAAkKSyILCgBmAwAYAAkKSyILCgBmAwAAAA==.Moraa:BAAANQAECgEIAQAAAA==.Moregoth:BAAANQAECgMJBQAAAA==.Morrows:BAAANQAECgcIEwAAAA==.Mossyoaks:BAAANQAECgEIAQAAAA==.Mossytank:BAAANQAECgIIAgAAAA==.Mossywarrior:BAAANQADCgIJAQAAAA==.',
Mu='Muggle:BAAANQADCgcJCwAAAA==.Multiply:BAAANQAECgYICwAAAA==.Murph:BAAANQAECgMIAwAAAA==.Murphgoat:BAAANQAECgYIDgAAAA==.Mutilatee:BAACNQAFFIEhAAMKAAgKqCQMAABbAwAKAAgKxSEMAABbAwAaAAYKyR0zAQBKAgA1AAQKgSwABAoACQrkJo8FAFIDAAoACAoyJI8FAFIDABoABwrMJcQIANUCACQAAQqgIRYWAEwAAAAA.',
My='Myeyeonu:BAAANQADCgYIHgABNQAECgIIBAAFAAAAAA==.Myrollan:BAAANQADCgYIBgAAAA==.Mystampede:BAAANQAFFAEIAQABNQAECgkJMAANALUkAA==.Mystshots:BAAANQAECgYICwAAAA==.',
['Mí']='Míra:BAABNQAECoE5AAIQAAgKwiVZBwBsAwAQAAgKwiVZBwBsAwAAAA==.',
['Mø']='Møzrt:BAAANQADCggIGwABNQAECgYIDAAFAAAAAA==.',
Na='Nachtengel:BAABNQAECoEYAAIeAAgKpgZ5iABuAQAeAAgKpgZ5iABuAQAAAA==.Nagda:BAAANQADCgYIBgAAAA==.Naismene:BAAANQAECgUICgAAAA==.Naismine:BAAANQAECgEIAQAAAA==.Namswoam:BAAANQAECgMIBAAAAA==.Nate:BAAANQAECgQIBQAAAA==.Naustaire:BAAANQADCgUIBQAAAA==.Nazendrenz:BAABNQAECoEnAAQeAAkKIiGpHgDYAgAeAAgKlSCpHgDYAgAfAAQK5xHCKQAXAQAgAAIKCw8VGgBxAAAAAA==.',
Nc='Nconceivable:BAAANQADCgUIBQAAAA==.',
Ne='Nebieul:BAAANQAECgQJBAAAAA==.Necromantic:BAABNQAECoEYAAMBAAcKSSPWFwDDAgABAAcKSSPWFwDDAgAQAAUKMRk3VwBRAQAAAA==.Neihtdk:BAAANQAECgUJCAAAAA==.Nerissraven:BAABNQAECoEUAAIeAAYKpyPwOgBlAgAeAAYKpyPwOgBlAgAAAA==.Nesaru:BAAANQAECgYIEgAAAA==.Nesho:BAAANQADCgQIBAAAAA==.Nesse:BAAANQADCggIDQAAAA==.Nestah:BAAANQAECgUIDgAAAA==.Neundorff:BAAANQADCgIIAgAAAA==.',
Ni='Niemira:BAAANQADCgQIBAAAAA==.Nighthunter:BAAANQAECgMJAwAAAA==.Nightshift:BAAANQADCgIIAgAAAA==.Nightwatch:BAABNQAECoEUAAIDAAcKjRzhNwBIAgADAAcKjRzhNwBIAgAAAA==.Niki:BAAANQAECgYICQAAAA==.Nisaloth:BAAANQAECgQJBQAAAA==.',
No='No:BAAANQADCgEIAQAAAA==.Nonaz:BAAANQAECgQIBQAAAA==.Nonrahnu:BAAANQAECgMIAwAAAA==.Nontoxic:BAAANQAECgcIDAAAAQ==.Noodlemaker:BAABNQAECoEWAAMVAAgKtx4mEgCHAgAVAAgKEx0mEgCHAgAlAAMK8RX3GwDHAAAAAA==.Noop:BAAANQAECgEIAQAAAA==.Norot:BAAANQAECgIIAgAAAA==.Northcut:BAAANQAECgYIBgAAAA==.Nozomga:BAEANQABCgIIAwAAAA==.',
Nu='Nual:BAABNQAECoErAAIPAAkK2By1DADyAgAPAAkK2By1DADyAgAAAA==.Nualandvoid:BAAANQADCggICAABNQAECgkJKwAPANgcAA==.Nubur:BAAANQADCgEIAQAAAA==.Nudag:BAAANQAECgQICAAAAA==.Nukelele:BAAANQADCggIFAAAAA==.',
Ny='Nystanari:BAAANQAECgcIDQAAAA==.',
['Nà']='Nàturally:BAAANQAECgMIAwAAAA==.',
['Nï']='Nïghtmare:BAAANQADCgIIAwAAAA==.',
Oa='Oakendeath:BAAANQAECgYICwAAAA==.',
Od='Odania:BAABNQAECoEeAAIVAAcKqRr/GgAPAgAVAAcKqRr/GgAPAgAAAA==.',
Oh='Ohmâ:BAAANQABCgUICwAAAA==.',
Ol='Older:BAABNQAECoE5AAIHAAgKwiWgAwB1AwAHAAgKwiWgAwB1AwAAAA==.Olk:BAABNQAECoEcAAIYAAgKpR8rFwDkAgAYAAgKpR8rFwDkAgAAAA==.',
Om='Omari:BAAANQADCgcICwAAAA==.',
On='Onlytotems:BAAANQADCgUIBQAAAA==.',
Oo='Oohgabooga:BAAANQAFFAEIAQABNQAFFAIIBQATAPAhAA==.',
Or='Oreganodh:BAAANQADCgQIBAABNQAFFAgIHwAgAPceAA==.Oreganom:BAAANQAECgQICAABNQAFFAgIHwAgAPceAA==.Oreganosh:BAAANQADCgQIBQABNQAFFAgIHwAgAPceAA==.Oreganow:BAACNQAFFIEfAAQgAAgK9x4fAABFAgAgAAYKrRkfAABFAgAeAAYKqBueAgAWAgAfAAMKbyJ4AQAPAQA1AAQKgSwABB4ACQrCJrkCALgDAB4ACQrkJbkCALgDAB8ACAq6JdEBAEcDACAABArUJW4IALkBAAAA.Orenghar:BAABNQAECoEhAAICAAgKqh1pJgCPAgACAAgKqh1pJgCPAgAAAA==.',
Os='Os:BAAANQAECgEIAQAAAA==.',
Ov='Overbite:BAAANQADCgEIAQAAAA==.Overcast:BAAANQAECgQIBAAAAA==.',
Ow='Owlcapwn:BAAANQADCgUIBQAAAA==.',
Pa='Pajamajacks:BAABNQAECoEtAAMBAAkK/h+eFwDFAgABAAgKACGeFwDFAgAbAAYKTBm2LwC+AQABNQAFFAgIHQAYAFcVAA==.Paladracdad:BAAANQAECgMIAwAAAA==.Pallylujâh:BAEBNQAECoEVAAMWAAYKjSHRVwA8AgAWAAYKjSHRVwA8AgADAAQKGiAwdQBmAQAAAA==.Palmerz:BAAANQAECgIIAgAAAA==.Papi:BAAANQADCggIDAAAAA==.Papy:BAAANQADCgQJBAAAAA==.Pardak:BAAANQAECgQJBQAAAA==.Partition:BAAANQAECgQIBwAAAA==.Patchwork:BAAANQADCggIDQAAAA==.Pavlov:BAAANQAECgEIAQAAAA==.',
Pe='Pengpeng:BAABNQAECoEkAAMSAAkKSQ6KkgAYAgASAAkKSQ6KkgAYAgAMAAEKggvcNwA4AAAAAA==.Perryy:BAAANQAECgQIBQAAAA==.Persephenie:BAAANQADCggIBwAAAA==.Pesmerga:BAAANQAECgQIBQAAAA==.Pestis:BAAANQABCgMJAwAAAA==.Pestosham:BAAANQAECgYIBAAAAA==.Pestulence:BAAANQADCgMIAwAAAA==.Pewpew:BAAANQADCgEIAQAAAA==.',
Ph='Phaithe:BAAANQADCgQIBwABNQAECgUIDAAFAAAAAA==.Phantasm:BAAANQADCggIDAAAAA==.Phil:BAAANQADCgQIBAABNQAECgUICQAFAAAAAA==.Philibert:BAAANQABCgcICQAAAA==.Phriaa:BAAANQAECgQIBAABNQAECgUIDAAFAAAAAA==.Phungerclap:BAACNQAFFIELAAILAAcKmiLKAgB2AgALAAcKmiLKAgB2AgA1AAQKgT8AAwsACQr5JmAAAAgEAAsACQr5JmAAAAgEACYABQpnH3MSAKIBAAAA.',
Pi='Pikarfor:BAABNQAECoEUAAIaAAcKshpbEABWAgAaAAcKshpbEABWAgAAAA==.Pingu:BAACNQAFFIEYAAICAAcKGB7YAACkAgACAAcKGB7YAACkAgA1AAQKgSkAAgIACQpXJBsHAHADAAIACQpXJBsHAHADAAAA.',
Pk='Pkspyro:BAAANQAECgQICAAAAA==.',
Pl='Planckshock:BAAANQAECgEIAQABNQAFFAcIGAAcAOEjAA==.Planckwar:BAAANQAECggIDgABNQAFFAcIGAAcAOEjAA==.',
Po='Polarexpress:BAAANQAECgIIAwAAAA==.Ponfomage:BAAANQAECgQIBwAAAA==.Ponfop:BAAANQAECgIIBAABNQAECgQIBwAFAAAAAA==.Popicus:BAAANQAECgYICwAAAA==.Porridge:BAAANQAECgIIBQAAAA==.',
Pr='Pratz:BAAANQAECgcJEQAAAA==.Priestism:BAEANQAECggICAABNQAFFAgIIQAYAPAeAA==.Primordikal:BAABNQAECoEbAAIZAAkKdxpiBwDgAgAZAAkKdxpiBwDgAgAAAA==.Priscillå:BAAANQAECggIBAAAAA==.',
Pu='Pudders:BAACNQAFFIEdAAIYAAgKVxX0AADKAgAYAAgKVxX0AADKAgA1AAQKgSQAAhgACQqkJGQNAEIDABgACQqkJGQNAEIDAAAA.Punchfist:BAAANQAECgUIDgAAAA==.Puppy:BAAANQABCgcICgAAAA==.',
Pw='Pwdrtoastman:BAAANQABCggIDgAAAA==.',
Qu='Quartzviper:BAAANQADCgYICQAAAA==.Quickcast:BAABNQAECoEjAAMSAAkKjiHnJQAxAwASAAkK8SDnJQAxAwAMAAEKtCAmKwBfAAAAAA==.',
Ra='Raddru:BAAANQAECggIEgABNQAFFAcIIAAQAPwkAA==.Radel:BAACNQAFFIEgAAIQAAcK/CRQAADwAgAQAAcK/CRQAADwAgA1AAQKgTkAAhAACQo5JosBANUDABAACQo5JosBANUDAAAA.Radlyn:BAAANQAECggIEwABNQAFFAcIIAAQAPwkAA==.Radmonk:BAAANQAECgIIBAABNQAFFAcIIAAQAPwkAA==.Radpal:BAACNQAFFIEGAAIEAAMKeBXmBQC+AAAEAAMKeBXmBQC+AAA1AAQKgSYAAgQACQoCJwIAACIEAAQACQoCJwIAACIEAAE1AAUUBwggABAA/CQA.Radwar:BAABNQAECoEeAAMmAAkKmyYgAAAABAAmAAkKmyYgAAAABAALAAkKFgARNwEEAAAAAA==.Raesham:BAAANQAECgEIAQAAAA==.Ragemaster:BAAANQADCgYIDAAAAA==.Raginghunter:BAAANQADCgQJBAABNQADCgYIDAAFAAAAAA==.Raidbuff:BAAANQAECgIJAgAAAA==.Ralah:BAAANQAECgYIEQAAAA==.Ratdk:BAAANQAECgUIDQAAAA==.Raydoth:BAAANQAECgYICwAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Redi:BAAANQADCgYIBgAAAA==.Redouté:BAAANQADCgEIAQABNQAECgYICwAFAAAAAA==.Redsaint:BAAANQAECgUICwAAAA==.Reinys:BAAANQAECgYIDgAAAA==.Reload:BAAANQAECgIIAgABNQAECgcJEAAFAAAAAA==.Remiwolf:BAAANQADCggIDAAAAA==.Renniei:BAAANQAECgQIAwAAAA==.Renârd:BAAANQADCggICQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rezispacqt:BAAANQAECgEJAQAAAA==.',
Rh='Rheha:BAAANQADCgYIBgAAAA==.Rhizah:BAAANQAECgYIDwAAAA==.',
Ri='Richkrakbaby:BAAANQAECgQICQAAAA==.Riskytriscut:BAAANQADCgMIAwAAAA==.Riyan:BAAANQADCggIDgAAAA==.',
Ro='Rob:BAAANQAECgUJBwAAAA==.Robinhoød:BAAANQAECgUIDQAAAA==.Robinn:BAAANQAECgMIAwAAAA==.Rocknsham:BAAANQAECgMJAwAAAA==.Roosifer:BAAANQADCgIIAgAAAA==.Rossin:BAAANQAECgUIDAAAAA==.Routerslayrx:BAAANQAECgcICQABNQAECgkJKwAmAFwlAA==.Roxington:BAAANQADCggJDgAAAA==.',
Ry='Ryddlesr:BAAANQADCggICQAAAA==.Ryeshot:BAACNQAFFIEeAAIPAAgK2SMVAABVAwAPAAgK2SMVAABVAwA1AAQKgSwAAg8ACQqxJooAAOoDAA8ACQqxJooAAOoDAAAA.Ryukotsuei:BAAANQAECgUICwAAAA==.Ryzonc:BAAANQABCgIIAgAAAA==.',
Sa='Saeltare:BAAANQADCgYICgAAAA==.Saeros:BAAANQADCgEIAQAAAA==.Sagemister:BAAANQADCgIIAgAAAA==.Saidin:BAAANQABCgIIBAAAAA==.Sange:BAAANQADCgQIBwAAAA==.Sanguinet:BAAANQAECgIJBAAAAA==.Sarlina:BAABNQAECoExAAMNAAgKIxKwRgAEAgANAAgKIxKwRgAEAgAPAAEKSASHcAAeAAAAAA==.Sarrius:BAAANQABCgIIAgAAAA==.Sarudomi:BAACNQAFFIEIAAMYAAUKSBdEDABBAQAYAAQKfhVEDABBAQAHAAIKeA0OCwCaAAA1AAQKgR0AAxgACQr1If0OADEDABgACQr1If0OADEDAAcABAp3De08ANIAAAAA.Sarusham:BAAANQAECgQICAAAAA==.Saruu:BAAANQAECgYJBgAAAA==.Saruwu:BAAANQADCgQIBAAAAA==.Sarïss:BAAANQAECgcJDgAAAA==.Savviana:BAAANQAECgIIAgAAAA==.',
Sb='Sbw:BAAANQAECgQIBQABNQAFFAUICQAUAIoTAA==.',
Sc='Scalemor:BAAANQAECgcIEwAAAA==.Scales:BAAANQADCgUICAAAAA==.Scarlah:BAAANQAECgEIAQAAAA==.Sciel:BAAANQAECgUIDgAAAA==.Scrabbles:BAAANQAECgcIEgAAAA==.',
Se='Secretwife:BAAANQAECgYICAAAAA==.Senara:BAAANQAECgYIEQAAAA==.Sendriss:BAAANQAECgQIBAAAAA==.Sephoniara:BAAANQAECgEIAQAAAA==.Sephonie:BAAANQADCgIIAwAAAA==.Serath:BAAANQAECgMJBAAAAA==.Setralan:BAAANQABCgQIBAAAAA==.',
Sh='Shaded:BAAANQABCgIIAgAAAA==.Shadowfactor:BAAANQAECgIIAgAAAA==.Shadowhawks:BAAANQAECgUICwAAAA==.Shadownej:BAAANQAECgIIAgAAAA==.Shadowsteel:BAAANQADCgkJEAAAAA==.Shamonlee:BAAANQAECgUIEAAAAA==.Shamydracdad:BAAANQADCggIDgABNQAECgMIAwAFAAAAAA==.Shapaladin:BAAANQADCggICAABNQAECgMIBQAFAAAAAA==.Sheepdoll:BAAANQAECgcIEwAAAA==.Shengo:BAAANQADCgEIAQAAAA==.Sherfin:BAAANQAECgEIAQAAAA==.Sheshindy:BAABNQAECoEWAAIgAAcKqA2aCACyAQAgAAcKqA2aCACyAQAAAA==.Shiftfour:BAAANQABCgEIAQAAAA==.Shiftysmom:BAABNQAECoExAAILAAgKaRiDUABYAgALAAgKaRiDUABYAgAAAA==.Shigz:BAAANQADCgYIBgABNQAECgYIDgAFAAAAAA==.Shinigamì:BAAANQAECgQIDAAAAA==.Shocklock:BAAANQAECggJEAAAAA==.Shogun:BAABNQAECoEZAAITAAgKqxEwKwDxAQATAAgKqxEwKwDxAQAAAA==.Shortypie:BAAANQABCgIIAgAAAA==.Shrimpngrits:BAAANQADCgIJAQAAAA==.Shámázing:BAAANQAECgQIBgAAAA==.Shåcø:BAABNQAECoErAAMKAAkK3CBiBgBCAwAKAAkKaCBiBgBCAwAaAAgKBBt2EgA8AgABNQAECgkKKwAKANwgAA==.',
Si='Sickmoves:BAAANQADCgQIBAAAAA==.Sillyheals:BAAANQADCggICQABNQAECgcIDgAFAAAAAA==.Sillyness:BAAANQADCgcJBgABNQAECgcIDgAFAAAAAA==.Sillypálly:BAAANQAECgcIDgAAAA==.Sinatra:BAAANQADCgMIBAAAAA==.Sindorael:BAAANQADCgQIBAAAAA==.Sinknight:BAAANQAECgcJCgAAAA==.Sithweaver:BAAANQADCgUIBgAAAA==.',
Sk='Skateorpie:BAAANQAECgYIEAAAAA==.Skeebadae:BAABNQAECoEXAAIZAAgKRxp2CwCCAgAZAAgKRxp2CwCCAgAAAA==.Skelestar:BAABNQAECoEaAAIYAAgKFSJiEwAHAwAYAAgKFSJiEwAHAwAAAA==.Skrt:BAAANQADCgIIAgAAAA==.Skullx:BAAANQADCggICgABNQAECgkJGAASAHYYAA==.Skytanks:BAAANQADCgUIBQAAAA==.Skädir:BAAANQAECgEIAQABNQAECgkJJAASAEkOAA==.',
Sl='Slayabunny:BAABNQAECoEdAAMLAAgKGyIWLgDWAgALAAgK/iAWLgDWAgAmAAUKMRg8GQBBAQAAAA==.Slep:BAAANQAECgYIDwAAAA==.Slepslep:BAAANQADCggICAABNQAECgYIDwAFAAAAAA==.Slepybaer:BAAANQADCgYJCAABNQAECgYIDwAFAAAAAA==.Slimzilla:BAABNQAECoEsAAMbAAkKnSG2BwBFAwAbAAkKfSG2BwBFAwABAAQKNhCEdgDQAAAAAA==.',
Sm='Smaugkfc:BAAANQAECggIBgABNQAFFAMIBwAGAE0YAA==.Smaugkitten:BAAANQADCgUIBQABNQAFFAMIBwAGAE0YAA==.Smaugvoker:BAAANQADCgYICQABNQAFFAMIBwAGAE0YAA==.Smegatron:BAAANQAECgUIDQAAAA==.Smoosh:BAAANQAECgYICgAAAA==.',
Sn='Sneakyaggro:BAAANQADCgcIBwABNQAECgQICAAFAAAAAA==.Sneakyheals:BAAANQAECgQICAAAAA==.Sneakyrage:BAAANQAECgYIDwAAAA==.Snipedya:BAAANQAECgYIDQAAAA==.Snolin:BAAANQAECgIJBAAAAA==.Snowblowwer:BAAANQADCgIIAgAAAA==.Snowyrainz:BAAANQAECgIIAwAAAA==.',
So='Soliat:BAAANQAECgUIEQAAAA==.Sooblysham:BAAANQAECgYIBwAAAA==.Soulshadez:BAAANQADCggICAAAAA==.Southpau:BAAANQABCgUIBQABNQAECgYIBgAFAAAAAA==.Souupded:BAAANQAECgcIEQAAAA==.',
Sp='Spamzvoltz:BAAANQAECgcIDQAAAA==.Sparklies:BAAANQADCgMIBAABNQAECgMIAwAFAAAAAA==.Spedometers:BAAANQAECgUIDgAAAA==.Spedometre:BAAANQAECgIIAgABNQAECgUIDgAFAAAAAA==.Spee:BAAANQABCgQIBAAAAA==.Sprinkel:BAAANQADCgMIAwAAAA==.',
Sq='Squrly:BAAANQABCgIJBAAAAA==.',
Ss='Ssjryukan:BAAANQADCgYICwAAAA==.',
St='Stacybeam:BAABNQAECoEXAAIGAAkKUx4kDQDzAgAGAAkKUx4kDQDzAgAAAA==.Standune:BAAANQAECgUICQAAAA==.Starrie:BAAANQAECgcJBwAAAA==.Staticshock:BAAANQAECgEIAQAAAA==.Steakñbake:BAAANQADCggIDwAAAA==.Stealthylick:BAAANQAECgUICwAAAA==.Stelus:BAAANQAECgUIDQAAAA==.Stereosity:BAAANQAECgQIBgABNQAECgkJMAANALUkAA==.Stickobutter:BAAANQAECgYIDwAAAA==.Stoicism:BAAANQAECgIIAQAAAA==.Stopngo:BAAANQADCggJBwAAAA==.',
Su='Sukuna:BAAANQAECgQICAAAAA==.Sunai:BAAANQAECgIIAwAAAA==.Suntra:BAAANQADCgMIAwAAAA==.Supbro:BAAANQADCgMIAwAAAA==.Suspenders:BAAANQAECgUICwAAAA==.',
Sy='Sykodude:BAABNQAECoEaAAIIAAgKhBqgOwBxAgAIAAgKhBqgOwBxAgAAAA==.Sykodudet:BAAANQAECgEIAQABNQAECggIGgAIAIQaAA==.Sykomage:BAAANQABCgUJBQAAAA==.Sykototem:BAAANQADCgQIBAABNQAECggIGgAIAIQaAA==.Sylvanassimp:BAAANQAECgUIDAAAAA==.Syrac:BAAANQADCgYIBgAAAA==.',
Ta='Taelil:BAAANQAECgIIBAAAAA==.Tailented:BAAANQAECgcIEwAAAA==.Takadra:BAAANQADCggIHQAAAA==.Tanalock:BAAANQAECgUIDQAAAA==.Tanalord:BAABNQAECoEbAAISAAkK9iS1BgC5AwASAAkK9iS1BgC5AwABNQAFFAUIBwAGAOEgAA==.Tarly:BAAANQADCgQIBAAAAA==.Taro:BAAANQAECgQIBgAAAA==.Tatertot:BAABNQAECoEdAAICAAgKZR56IwCgAgACAAgKZR56IwCgAgAAAA==.Tayrn:BAAANQAECgEIAQAAAA==.',
Te='Teaswift:BAAANQAECgUIBwABNQAECgUIEgAFAAAAAA==.Temuwhooper:BAAANQAECgQIBAABNQAECgkJMAANALUkAA==.',
Th='Thalyn:BAAANQADCgQIBAABNQAECggIGAAHAMYNAA==.Thandaril:BAAANQAECgEIAQAAAA==.Tharn:BAAANQADCgYJBgABNQADCggICAAFAAAAAA==.Thebabadook:BAAANQADCggIJwAAAA==.Theduckler:BAAANQADCgUIBQAAAA==.Thelonliest:BAAANQAECgUIEgAAAA==.Thornstaad:BAAANQAECgUIDgAAAA==.Thortanous:BAAANQADCggIEAAAAA==.Thrashmor:BAAANQAECgMJAwAAAA==.Throckmortus:BAAANQAECgMIAwAAAA==.Thuggymage:BAABNQAECoEwAAISAAgKFxbUjQAjAgASAAgKFxbUjQAjAgAAAA==.Thunderboom:BAAANQAECgYIDQAAAA==.Thundercles:BAAANQAECgUICQAAAA==.Thunderstruk:BAAANQADCgQIBAAAAA==.Thyself:BAAANQAECgcIEwAAAA==.Thór:BAAANQADCgUIBQAAAA==.',
Ti='Tidebadra:BAABNQAECoEhAAIZAAgK8CMWAwBbAwAZAAgK8CMWAwBbAwAAAA==.Tideradra:BAACNQAFFIEiAAMUAAcKZiFnAADZAgAUAAcKZiFnAADZAgACAAEKZAMnJAA6AAA1AAQKgSEAAxQACQqrJZwEALoDABQACQqrJZwEALoDAAIACApmDttkAIcBAAAA.Ting:BAAANQAECgUIBwAAAA==.',
Tk='Tkd:BAAANQAECgEIAQABNQAECgQJCgAFAAAAAA==.',
To='Toats:BAAANQADCgUIBwAAAA==.Toixic:BAAANQAFFAEIAQABNQAFFAgIHQACAMcNAA==.Toixtem:BAACNQAFFIEdAAICAAgKxw0IAQCRAgACAAgKxw0IAQCRAgA1AAQKgRgAAgIACQr1IL0cAMcCAAIACQr1IL0cAMcCAAAA.Tomfoolery:BAAANQADCgQIBAAAAA==.Tootihunt:BAACNQAFFIEPAAMJAAUKOCPrCABoAQAJAAQKfxzrCABoAQAIAAIKUCU3EADcAAA1AAQKgSIAAwkACQp6JFAGAFYDAAkACQocJFAGAFYDAAgABwoXHaJyANABAAAA.Topg:BAAANQAECgQICAAAAA==.Totmdispenzr:BAAANQAECgIIAgAAAA==.Toukai:BAAANQADCggIGwABNQAECgUICwAFAAAAAA==.Toukuhd:BAAANQAECgUICwAAAA==.',
Tr='Traia:BAAANQADCgYICgAAAA==.Tralinadia:BAAANQADCggICAAAAA==.Travaxian:BAAANQADCgYIBgAAAA==.Trendz:BAAANQABCgQICQAAAA==.Trihold:BAAANQADCgEIAQAAAA==.Trog:BAAANQADCgUIBQAAAA==.',
Ts='Tselli:BAAANQAECgQICQABNQAECgkJJgAZAC8hAA==.Tsellie:BAABNQAECoEmAAMZAAkKLyG0AgBpAwAZAAkKLyG0AgBpAwACAAYKJho5YACXAQAAAA==.Tselliepally:BAAANQAECgYICAABNQAECgkJJgAZAC8hAA==.',
Tu='Tulas:BAAANQAECgEIAgAAAA==.Tumbler:BAAANQAECgQIBwAAAA==.Turkleton:BAAANQAFFAIIAgAAAA==.',
Tw='Twobelow:BAAANQADCgEIAQAAAA==.Twístedteå:BAAANQAECgMIBQAAAA==.',
Ty='Tylos:BAAANQADCggIDAAAAA==.Tyraxous:BAAANQAECgYIDwAAAA==.Tyrinnà:BAAANQADCgYICgAAAA==.',
['Tö']='Törryn:BAAANQAECgYIDwAAAA==.',
Ul='Ulah:BAAANQADCgcIHQAAAA==.',
Un='Unholyarrie:BAAANQADCgEIAQAAAA==.Unholybaine:BAAANQADCgIIAgAAAA==.Unknownz:BAABNQAECoEWAAMBAAkKix2gOgDVAQABAAcKlx2gOgDVAQAbAAgKshLxLgDEAQAAAA==.Unstopubble:BAABNQAECoE5AAIEAAgK1SCNBwD5AgAEAAgK1SCNBwD5AgAAAA==.',
Up='Upyouràrthas:BAAANQAECgMIBAAAAA==.',
Us='Ushinoken:BAAANQABCgEIAQAAAA==.',
Uu='Uuchi:BAAANQAECgQIBQAAAA==.',
Va='Vaariks:BAAANQAECgYIEQAAAA==.Vaera:BAAANQAECgQICAAAAA==.Valeindia:BAAANQAECgQIAgAAAA==.Valenia:BAAANQAECggICAAAAA==.Valianthe:BAAANQAECgUICQAAAA==.Valner:BAAANQAECgUIDgAAAA==.Valthyria:BAAANQAECgcJDgAAAA==.Vandamnit:BAAANQADCgcIBwAAAA==.Vanessaboo:BAAANQAECggIEAABNQAFFAgIHQABAFslAA==.',
Ve='Vebel:BAAANQAECgEIAgAAAA==.Vegara:BAAANQADCgMIAwAAAA==.Velthyr:BAAANQADCgIIAgABNQADCggICAAFAAAAAA==.Velínthelyn:BAAANQADCgUIBAAAAA==.Vexthall:BAAANQADCgIIAgAAAA==.',
Vi='Vikingdrood:BAABNQAECoETAAIYAAgKwhnyKwA6AgAYAAgKwhnyKwA6AgAAAA==.Vikingj:BAAANQADCggIEAABNQAECggIEwAYAMIZAA==.Vikingsham:BAAANQADCgcIBwABNQAECggIEwAYAMIZAA==.Vinnyfr:BAABNQAECoEpAAMaAAkKCR+VBAA3AwAaAAkKCR+VBAA3AwAKAAgKshPPIgAPAgAAAA==.Virsaviya:BAAANQAECgQIBAAAAA==.Viwi:BAAANQAECgYIDgAAAA==.',
Vo='Voidmelky:BAAANQADCgIIAgAAAA==.',
Vu='Vulair:BAAANQAECgUIBgABNQAECgkJKQATAD8aAA==.',
Vy='Vyrandar:BAAANQADCggICQAAAA==.',
Wa='Warraxrage:BAABNQAECoEtAAMLAAkKoR7TJAD/AgALAAkKcx7TJAD/AgARAAQKSBsbEABQAQAAAA==.Warwings:BAAANQAECgQIBAAAAA==.Watanabi:BAAANQAECgQIBQAAAA==.',
We='Welky:BAAANQADCgIIAgAAAA==.',
Wh='Wheel:BAAANQAECgcIEwAAAA==.',
Wi='Winc:BAAANQADCgIIAgAAAA==.',
Wo='Wonsmash:BAAANQAECgYIDgAAAA==.',
Wy='Wynndiego:BAABNQAECoEYAAIYAAcK+BCXPQC5AQAYAAcK+BCXPQC5AQAAAA==.Wyrmslayer:BAACNQAFFIEIAAILAAQKRxMWEABCAQALAAQKRxMWEABCAQA1AAQKgRoAAgsACQrTH7AkAP8CAAsACQrTH7AkAP8CAAAA.',
Xa='Xaidra:BAACNQAFFIElAAIhAAgK8REDAQCeAgAhAAgK8REDAQCeAgA1AAQKgSwAAiEACQoDIfsGABoDACEACQoDIfsGABoDAAAA.Xanatu:BAAANQAECgYIDQAAAA==.Xandyr:BAAANQADCgUIBgAAAA==.',
Xe='Xedk:BAABNQAECoEiAAIBAAgKgw97QAC1AQABAAgKgw97QAC1AQAAAA==.Xenzlok:BAAANQAECgQIBAABNQAECgYIEQAFAAAAAA==.Xepherite:BAAANQAECgUJBwABNQAFFAMIBgAUALcgAA==.Xephsham:BAACNQAFFIEGAAIUAAMKtyCSDAAqAQAUAAMKtyCSDAAqAQA1AAQKgRsAAhQACQrdIoAPAFIDABQACQrdIoAPAFIDAAAA.Xetholosa:BAAANQAECgQICAAAAA==.Xethoscope:BAAANQAECgMIBQAAAA==.',
Ya='Yarayara:BAAANQADCggICAAAAA==.Yautja:BAAANQAECgMIAwABNQAECgcIGwAGAOgWAA==.',
Yo='Yogafire:BAAANQADCgcIBwABNQAECgUIDwAFAAAAAA==.Yozu:BAAANQADCgEIAQAAAA==.',
Yu='Yuimage:BAAANQAECgUJCgAAAA==.',
['Yö']='Yögifox:BAAANQAECgMJAwABNQAECgQIBQAFAAAAAA==.',
Za='Zaene:BAAANQAECgUICgAAAA==.Zafyria:BAAANQAECgUIDwAAAA==.Zalea:BAACNQAFFIEkAAISAAgKpCJPAABKAwASAAgKpCJPAABKAwA1AAQKgTIAAhIACQpiJv8BAOUDABIACQpiJv8BAOUDAAAA.Zaluid:BAAANQAECgYJCQABNQAFFAgIJAASAKQiAA==.',
Ze='Zekkial:BAABNQAECoEXAAIZAAgKbxmnCwB+AgAZAAgKbxmnCwB+AgAAAA==.Zendroza:BAAANQADCggJFwABNQAECgUIDgAFAAAAAA==.Zerks:BAAANQADCgQIBAAAAA==.',
Zi='Zippyzapper:BAAANQAECgIIAwAAAA==.',
Zl='Zlliks:BAAANQADCgQIBAAAAA==.',
Zo='Zoekai:BAAANQAECgUICwAAAA==.Zolar:BAAANQADCggJDAAAAA==.Zonovar:BAABNQAECoElAAIZAAkKSiO9AQCRAwAZAAkKSiO9AQCRAwAAAA==.',
Zu='Zurks:BAABNQAECoEjAAMOAAgK5BgRBABgAgAOAAgK5BgRBABgAgAPAAEKhwMzaQAmAAAAAA==.Zurkz:BAABNQAECoEVAAIHAAkK2h5rBQBLAwAHAAkK2h5rBQBLAwAAAA==.',
['Zà']='Zàddy:BAAANQAECgcIDgAAAA==.',
['Äz']='Äzalea:BAAANQADCggJCAAAAA==.Äzræll:BAAANQADCggIFgAAAA==.',
['Ås']='Åshborn:BAAANQAFFAIIBAAAAA==.',
['Ér']='Érìs:BAAANQAECgUICAABNQAECggIGQALAMEZAA==.',
['Ði']='Ðixiewrecked:BAAANQAECgcIEQAAAA==.',
['Ðu']='Ðuck:BAAANQADCggJDgAAAA==.',
['ßo']='ßooyeah:BAAANQAECgQIBAAAAA==.',
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
