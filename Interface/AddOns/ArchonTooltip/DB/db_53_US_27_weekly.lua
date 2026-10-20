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

local lookup = {'Mage-Arcane','Druid-Guardian','Hunter-Survival','DeathKnight-Frost','Paladin-Retribution','Warlock-Demonology','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Warlock-Destruction','Unknown-Unknown','Mage-Frost','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Protection','Shaman-Restoration','Priest-Shadow','Rogue-Subtlety','Paladin-Holy','DemonHunter-Havoc','Warlock-Affliction','Evoker-Devastation','Druid-Balance','Rogue-Assassination','Priest-Holy','Evoker-Preservation','Shaman-Elemental','Priest-Discipline','Rogue-Outlaw','Evoker-Augmentation','Druid-Restoration',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaravos:BAAANQAECgYIBgAAAA==.Aatrøx:BAAANQAECgUICgAAAA==.',
Ac='Accretion:BAAANQADCgcICAAAAA==.',
Ad='Addath:BAAANQAECgUIBAAAAA==.Adura:BAAANQADCggICgAAAA==.',
Ae='Aeirith:BAABNQAECn8kAAIBAAoK4hUkjwBhAgABAAoK4hUkjwBhAgAAAA==.',
Ai='Ailsà:BAAANQADCgIJAgABNQAECgYIFQACAOkRAA==.Airius:BAAANQAECgEIAQAAAA==.',
Al='Alannon:BAAANQADCgQIBQAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMIAwAAAA==.',
Am='Amalthia:BAAANQAECgUIBwAAAA==.Amarasu:BAABNQAECn8ZAAIDAAcK9BHpBwDlAQADAAcK9BHpBwDlAQAAAA==.Amarlly:BAABNQAECn8XAAIEAAYKAhR4RwCgAQAEAAYKAhR4RwCgAQAAAA==.',
An='Ancelina:BAAANQAECgUIDwAAAA==.Anderton:BAABNQAECn8rAAIFAAgKqxBSwwCVAQAFAAgKqxBSwwCVAQAAAA==.Andilocks:BAAANQADCggIJwAAAA==.Anditracks:BAAANQADCggIHwAAAA==.Andraenei:BAAANQAECgUIEgAAAA==.Andrela:BAAANQAECgIIAQAAAA==.Andromadda:BAAANQADCgcIBwAAAA==.Aneira:BAABNQAECn8VAAICAAYK6RFlFgDRAAACAAYK6RFlFgDRAAAAAA==.',
Ap='Applefritter:BAAANQADCggIDQABNQAECggIHQAGAJoZAA==.',
Aq='Aquarius:BAAANQADCgcICQAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECn84AAIHAAoKmyMXBAAgAgAHAAoKmyMXBAAgAgAAAA==.Archmedies:BAAANQADCgEIAQAAAA==.Archérhiro:BAACNQAFFH8WAAMIAAYKExvuBwDNAQAIAAYKExvuBwDNAQAJAAEKAAAfKAA1AAA1AAQKfzgAAwgACgpuI/4UAEkDAAgACgpuI/4UAEkDAAkABQpTEANFADEBAAAA.Arillann:BAABNQAECn8lAAIKAAoKDx3aBwAjAwAKAAoKDx3aBwAjAwAAAA==.Arin:BAAANQAECgQIBgABNQAECgoKGgALACoWAA==.Arms:BAAANQAECgEIAwABNQAECgkJIQAFAEAVAA==.Arrook:BAAANQAECgEIAQAAAA==.Artdemsamis:BAABNQAECn8XAAMMAAkKiRAWNgDpAAAGAAcK2g6ymACpAQAMAAQKqw4WNgDpAAAAAA==.Arttimar:BAAANQAECggICAAAAA==.Arvena:BAAANQADCgQIBAAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgANAAAAAA==.Ashylock:BAABNQAECn8aAAIGAAoKgxPKUQBgAgAGAAoKgxPKUQBgAgABNQAFFAUIDgABANMNAA==.Ashymage:BAACNQAFFH8OAAIBAAUK0w1tIgB0AQABAAUK0w1tIgB0AQA1AAQKfzwAAwEACgrLIsgWAHgDAAEACgrLIsgWAHgDAA4AAQrTCu1GADYAAAAA.Askevar:BAABNQAECn8bAAIPAAYKXAgcJwDJAAAPAAYKXAgcJwDJAAAAAA==.Asriél:BAABNQAECn8YAAIIAAgK7Rj1YwBNAgAIAAgK7Rj1YwBNAgAAAA==.Assoul:BAAANQADCgEIAQAAAA==.Astrea:BAAANQADCgEIAQAAAA==.Astridia:BAAANQAECgIIAwAAAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.Atreus:BAAANQAECgcIDwAAAA==.',
Az='Azaleah:BAABNQAECn8vAAIFAAoKshCGMwBmAQAFAAoKshCGMwBmAQAAAA==.Azatal:BAAANQADCgEIAgAAAA==.Azlan:BAAANQAECgEIAgAAAA==.Azraesha:BAABNQAECn8bAAIQAAoKIhCjDQBJAQAQAAoKIhCjDQBJAQAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Ba='Backy:BAAANQAECgUIBAAAAA==.',
Be='Beareold:BAAANQAECgEIAgAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQIDQAAAA==.Bigmon:BAABNQAECn9JAAMLAAoKTyBsIQAyAwALAAoKTyBsIQAyAwARAAEKgA/SRAAvAAAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgQIBgAAAA==.Blackstaff:BAAANQADCggIEQAAAA==.Blessthefall:BAAANQAECggIBgAAAA==.Bloke:BAAANQADCgEIAQAAAA==.Bloodygrundl:BAABNQAECn8jAAIHAAoKOyBVEAAqAwAHAAoKOyBVEAAqAwAAAA==.Bluestorm:BAAANQAECgYIEAAAAA==.Bluestreak:BAAANQADCgEIAgAAAA==.',
Bo='Bonegrinda:BAABNQAECn8iAAIPAAgKdx6rMgBhAgAPAAgKdx6rMgBhAgAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwANAAAAAA==.',
Br='Branwynn:BAAANQAECgIIAgAAAA==.Bringg:BAAANQAECgQIBAAAAA==.',
Bu='Budgetcuts:BAAANQADCgYIBgAAAA==.Bulldoza:BAAANQADCgQIBAAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgEIAQAAAA==.Calliaa:BAAANQADCgYIBgAAAA==.Callmemommy:BAAANQAECgEIAgAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAAANQAECgYIDQAAAA==.Ceri:BAAANQAECggIAQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFH8XAAISAAcK1h8LBABFAgASAAcK1h8LBABFAgA1AAQKfygAAhIACgoAJfQIAHoDABIACgoAJfQIAHoDAAAA.Chantix:BAAANQADCgYIBwAAAA==.Chaosshadow:BAABNQAECn8eAAITAAcKXhOXCgBOAQATAAcKXhOXCgBOAQAAAA==.Chaosti:BAABNQAECn8UAAIPAAcK3gt2bABhAQAPAAcK3gt2bABhAQAAAA==.Cheekymonkey:BAABNQAECn8mAAIBAAgKjgnpaQDpAAABAAgKjgnpaQDpAAAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Chueyé:BAAANQADCgUIBQABNQAECgoKMAAUAIYeAA==.Chune:BAAANQADCgEIAQAAAA==.Churros:BAAANQAECgYICgABNQAECggIHQAGAJoZAA==.',
Co='Cobiepaladin:BAAANQAECgYIBgAAAA==.Coconuts:BAAANQAECgEIAQAAAA==.Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAABNQAECn8mAAIVAAYKtR2ecwC9AQAVAAYKtR2ecwC9AQAAAA==.Crosslock:BAAANQADCgcICwAAAA==.',
Cu='Cuack:BAAANQAECgEIAQAAAA==.',
Cy='Cynnari:BAABNQAECn8cAAIGAAcKawd/wABLAQAGAAcKawd/wABLAQAAAA==.',
Da='Dagnabit:BAAANQADCggIHgAAAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAABNQAECn8XAAIWAAcKKA9fQgCuAQAWAAcKKA9fQgCuAQAAAA==.Darkeon:BAAANQADCgEIAQAAAA==.Darkpriestes:BAAANQADCgQIBAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgUIDwAAAA==.Dartian:BAAANQAECgMJAwABNQAECgcIFwAIALQJAA==.',
De='Deathmare:BAAANQAECgcIDgAAAA==.Deeptroat:BAAANQADCgEIAQABNQAECgcIGQADAPQRAA==.Dementia:BAAANQADCgcIBwAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAABNQAECn8mAAMGAAgK0BPqdQAAAgAGAAgK0BPqdQAAAgAXAAEKAAAfMQAzAAAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAABNQAECn8VAAQEAAUKiA8uPgCrAAAEAAQKQw8uPgCrAAAPAAIKtQRBzABUAAAHAAEK0g1PywAzAAAAAA==.Diltlish:BAAANQAECgQICAAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAABNQAECn8lAAILAAkKrBklfwAdAgALAAkKrBklfwAdAgAAAA==.',
Dm='Dmginc:BAAANQAECgMIBwAAAA==.',
Do='Doeblin:BAAANQAECgEIAQAAAA==.Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgMIAwAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Drackonia:BAAANQAECgUIDwAAAA==.Dracolyte:BAAANQADCgEIAQAAAA==.Dragonflai:BAABNQAECn8jAAIBAAoKsA8znwBDAgABAAoKsA8znwBDAgAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQAECgUICAAAAA==.Drakkei:BAABNQAECn8kAAIIAAoKgxDubAA4AgAIAAoKgxDubAA4AgAAAA==.Drshortbus:BAAANQAECgUICQAAAA==.Drunkenfist:BAAANQAECgQIBQAAAA==.Drylo:BAEBNQAECn8kAAIYAAgKNyMoBgAqAwAYAAgKNyMoBgAqAwAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
Ed='Edelweíss:BAAANQAECgEIAQAAAA==.',
El='Elarol:BAAANQADCgYICQAAAA==.Eldons:BAAANQADCgEIAQAAAA==.Eleonore:BAAANQAECgYIDQAAAA==.Elfie:BAAANQADCgYIBgAAAA==.Elray:BAAANQAECgUIBwAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQADCgEIAQAAAA==.Emptyhands:BAAANQAECgcICQAAAA==.Emptyheals:BAAANQADCggIDQAAAA==.',
En='Endrin:BAAANQAECgEIAQAAAA==.',
Ep='Epiq:BAAANQADCgEIAwAAAA==.',
Er='Erf:BAAANQADCgYIDgAAAA==.Erfinden:BAAANQADCgIIBAAAAA==.',
Es='Espers:BAABNQAECn8kAAIZAAgKrw5qSwC3AQAZAAgKrw5qSwC3AQAAAA==.',
Et='Ethellin:BAABNQAECn8jAAIFAAcKpwTRBQEVAQAFAAcKpwTRBQEVAQAAAA==.',
Eu='Euph:BAAANQAECgUICQAAAA==.',
Ev='Evilhearts:BAAANQADCggICAAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDwAAAA==.',
Fe='Fedders:BAAANQAECgYIEwABNQAECgoKMAAFAOokAA==.Feedmepizzas:BAAANQAECgEIBAAAAA==.Feildmedic:BAAANQAECgUIBwABNQAECgUIEAANAAAAAA==.Feleria:BAAANQADCgUJBQAAAA==.Felwinter:BAAANQADCgYIBwAAAA==.',
Fi='Finwé:BAAANQAECgIIAgAAAA==.Fizzysoda:BAAANQADCgcIBwAAAA==.',
Fl='Fluxarata:BAAANQAECgcIEQAAAA==.',
Fr='Fred:BAAANQAECgQIDAAAAA==.Friendly:BAABNQAECn8mAAIaAAoK/iLXAAD1AgAaAAoK/iLXAAD1AgAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgUICQAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.Fupacabra:BAAANQADCgcIBwAAAA==.Fuzzyhunter:BAAANQADCgcICwAAAA==.',
['Fè']='Fènrïr:BAAANQADCgEIAgAAAA==.',
['Fï']='Fïzzle:BAAANQAECgQIBQABNQAECgYIFQACAOkRAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAABNQAECn8jAAIIAAoKLRbFPwCrAgAIAAoKLRbFPwCrAgAAAA==.Gagageoff:BAAANQAECgEIAQAAAA==.Gardyson:BAABNQAECn8lAAMRAAoKBgwfIABOAQALAAoKpAgcsQCiAQARAAcK1QwfIABOAQAAAA==.Garwarmegad:BAAANQADCggICwAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Gl='Gloney:BAAANQADCgMIAwAAAA==.',
Gn='Gnomew:BAAANQAECgMIAwAAAA==.',
Go='Gobsprocket:BAAANQADCggICAAAAA==.Gojira:BAAANQAECgEIAQAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAABNQAECn8qAAIJAAoKKBLvBgB5AQAJAAoKKBLvBgB5AQAAAA==.Grenadeout:BAAANQAECgYIDQAAAA==.Grimaldus:BAAANQAECgEIAQAAAA==.',
Ha='Harrod:BAAANQADCgYIBgAAAA==.Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQANAAAAAA==.',
He='Hefty:BAAANQAECgUIEAAAAA==.Hellbad:BAAANQAECggIEgAAAA==.Hellsspawn:BAAANQADCgUIDQAAAA==.',
Ho='Hokàge:BAABNQAECn8wAAMUAAoKhh5pBAAFAgAaAAcKLBwXLAA4AgAUAAkK/h1pBAAFAgAAAA==.Holyprom:BAAANQADCgUIBQAAAA==.Homealone:BAAANQAECgcIEQAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huey:BAAANQADCggIDwABNQAECggIHQATAKARAA==.Huntinfuzzy:BAABNQAECn8bAAIIAAgKjwmCWAD+AAAIAAgKjwmCWAD+AAAAAA==.Huugg:BAAANQAECgQIBAAAAA==.',
Hy='Hymncarrey:BAABNQAECn8eAAIbAAcKdiMrFgC/AQAbAAcKdiMrFgC/AQAAAA==.Hynkie:BAAANQAECgYIDwABNQAECgkJKQAcAG4YAA==.',
Id='Idari:BAAANQABCgEIAQAAAA==.',
Ig='Igothots:BAAANQAECgYICgABNQAECgcIDgANAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAABNQAECn8iAAQXAAkKyhmGAAAxAgAXAAkKyhmGAAAxAgAGAAYKXA5dtgBiAQAMAAEK4wZnfwAtAAAAAA==.',
Is='Isadragon:BAAANQADCgUICgABNQAECgcIGQADAPQRAA==.',
Ja='Jackyll:BAAANQAECggIBwAAAA==.Jatix:BAABNQAECn8aAAIFAAkKThjsbgBSAgAFAAkKThjsbgBSAgAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgQIBQANAAAAAA==.',
Je='Jellytown:BAABNQAECn8iAAIOAAoKNReMBQC3AgAOAAoKNReMBQC3AgAAAA==.Jelorinea:BAAANQADCgYIBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.Jethibaud:BAAANQADCgEIAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgQICQAAAA==.',
Ju='Juicylucy:BAAANQAECgEIAQAAAA==.Jundra:BAAANQADCgYICAAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQADCggIHgAAAA==.Justine:BAAANQAECgIIAwAAAA==.',
['Jô']='Jôhnwick:BAABNQAECn8dAAIJAAkKZw4UKwDyAQAJAAkKZw4UKwDyAQAAAA==.',
Ka='Kaedas:BAAANQADCgMIAwABNQAECgoKJAAIAIMQAA==.Kaerynn:BAAANQADCgYIBwAAAA==.Kait:BAABNQAECn8iAAIIAAoKzRG7UgB4AgAIAAoKzRG7UgB4AgAAAA==.Kaladil:BAAANQAECgEIAQAAAA==.Kashmir:BAAANQAECgMIAwAAAA==.Kawdor:BAAANQAECgQIBgAAAA==.Kazola:BAAANQADCgEIAgAAAA==.',
Ke='Kelaino:BAAANQABCgYIBgAAAA==.',
Kh='Khota:BAAANQAECgcICwAAAA==.',
Ki='Killanick:BAAANQAECgUIBQAAAA==.',
Ko='Koldfront:BAAANQADCgYIEAAAAA==.Kollinator:BAAANQAECgQIBAAAAA==.Korvonn:BAAANQADCgEIAQAAAA==.',
Kr='Krokrodale:BAAANQADCgEIAQAAAA==.',
Ku='Kurtina:BAABNQAECn8nAAILAAoKShOqNABBAQALAAoKShOqNABBAQAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAABNQAECn8XAAIIAAkKrRW1UQB7AgAIAAkKrRW1UQB7AgAAAA==.Larac:BAAANQAECggIDQAAAA==.',
Le='Leddy:BAAANQADCgUICwAAAA==.Leif:BAABNQAECn8iAAIYAAoK5hRqEABRAgAYAAoK5hRqEABRAgAAAA==.Lemmart:BAAANQAECgcIDwAAAA==.Lenik:BAAANQAECgYIEQAAAA==.',
Li='Licorice:BAABNQAECn8dAAMGAAgKmhlQbwARAgAGAAgKmhlQbwARAgAMAAEKEwvQewAxAAAAAA==.Lieree:BAABNQAECn8fAAIBAAgK/gn63gDKAQABAAgK/gn63gDKAQAAAA==.Lilyfaye:BAAANQADCgEIAQAAAA==.Limosfire:BAAANQAECgUIBwAAAA==.',
Lo='Lockty:BAAANQAECggIDgABNQAECgkJFwAIAK0VAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.Lorian:BAAANQAECgIIAwAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAEANQAECgIIAwAAAA==.Lucity:BAAANQAECggIDwABNQAECgkJGgAFAE4YAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQADCgYIEAAAAA==.Lunarmyst:BAAANQADCgUIBgABNQADCgEIAgANAAAAAA==.Lunà:BAAANQAECgQICQAAAA==.',
Ly='Lystral:BAAANQAECgQICgAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUIDgAAAA==.',
['Lá']='Lásh:BAAANQAECgUIBQABNQAECgYIFQACAOkRAA==.',
Ma='Mace:BAABNQAECn8fAAIFAAkKpyLRHgBIAwAFAAkKpyLRHgBIAwAAAA==.Magdalena:BAAANQAECgQIBQAAAA==.Mageyboi:BAAANQAECgMIAgABNQAECgoKMAAUAIYeAA==.Magickul:BAAANQAECgQIBwAAAA==.Mahano:BAAANQAECgEIAQABNQAECgoKJQARAAYMAA==.Malìficus:BAAANQADCgcICAAAAA==.Manadâr:BAAANQAECgUIBgAAAA==.Marinas:BAAANQADCgcIGQAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgEIBQAAAA==.Mazumaragg:BAAANQAECgMIBAABNQAECgoKJQARAAYMAA==.',
Me='Mello:BAAANQADCgUIBQAAAA==.',
Mi='Miande:BAAANQAECgYICgAAAA==.Microburst:BAABNQAECn8qAAIdAAkKrAdIHgBDAQAdAAkKrAdIHgBDAQAAAA==.Minilock:BAABNQAECn8hAAQGAAgKlwp1OgAcAQAGAAgKlwp1OgAcAQAMAAMKwgHqYQBhAAAXAAEKDAcpMgAwAAAAAA==.Missdeeds:BAAANQADCgEIAgAAAA==.Missleading:BAAANQADCgEIAwAAAA==.Missused:BAAANQAECgEIAQAAAA==.Miyagifu:BAAANQADCgMJBQABNQAECgUIEAANAAAAAA==.Mièlikki:BAAANQAECgUIDwAAAA==.',
Mo='Modelotime:BAAANQADCggICwAAAA==.Modsagoodtnk:BAAANQADCggICQAAAA==.Mondrin:BAAANQADCgEIAQAAAA==.Mongermook:BAABNQAECn8ZAAICAAgKRg2nKABRAQACAAgKRg2nKABRAQAAAA==.Monnkysham:BAAANQADCgYJBgAAAA==.Mooglefur:BAAANQADCgcICAAAAA==.Moranta:BAEANQADCgYIBwAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAABNQAECn8fAAISAAcKYxYiNwAIAQASAAcKYxYiNwAIAQAAAA==.Nacronor:BAAANQAECgEIAQAAAA==.Naiika:BAAANQADCgEIAQAAAA==.Nasoj:BAAANQAECgUIBAAAAA==.Nauseous:BAAANQADCggJCAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBwAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Newports:BAAANQADCggIIwAAAA==.Nexedo:BAAANQAECgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBgAAAA==.Nickelodeon:BAAANQAECgQICQAAAA==.Nickita:BAAANQAECgQIBwAAAA==.Nightgear:BAACNQAFFH8VAAIIAAYK2Q7fAwAhAgAIAAYK2Q7fAwAhAgA1AAQKf1MAAggACgotIXoBAA4DAAgACgotIXoBAA4DAAAA.Nighti:BAAANQADCgQIBAAAAA==.Niteshadeth:BAAANQADCgMIAwAAAA==.Nixeava:BAAANQAECgQICwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nygon:BAAANQADCgEIAQAAAA==.Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAABNQAECn8vAAMCAAkKqRMICgBaAQACAAgKrBYICgBaAQAZAAcKzwevZwAuAQABNQAECgoKJAAIAIMQAA==.',
Od='Ode:BAABNQAECn8nAAIBAAkKKwwbGQCrAQABAAkKKwwbGQCrAQAAAA==.Odex:BAAANQAECgYIDAAAAA==.',
On='Onlymages:BAABNQAECn8gAAIBAAcKMgsHmgCVAAABAAcKMgsHmgCVAAAAAA==.Onos:BAAANQAECgQICwAAAA==.',
Or='Orinin:BAABNQAECn8dAAMTAAgKoBFpLQC6AQATAAgKoBFpLQC6AQAeAAMKhgtAGwCOAAAAAA==.',
Ou='Outdeath:BAAANQAECgMIAwABNQAECgUICwANAAAAAA==.Outkíll:BAAANQAECgUICwAAAA==.',
Oz='Ozempic:BAAANQADCgEIAQAAAA==.',
Pa='Pally:BAABNQAECn8hAAIFAAkKQBWDfwAqAgAFAAkKQBWDfwAqAgAAAA==.Pandarweb:BAAANQAECgUIBgAAAA==.Papasmurfz:BAAANQAECgUIBQAAAA==.Pathogen:BAABNQAECn8jAAIPAAoKpiHqCQBuAwAPAAoKpiHqCQBuAwAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAABNQAECn8cAAIEAAgKxRGOEQB5AQAEAAgKxRGOEQB5AQAAAA==.Perve:BAAANQAECgcIEAABNQAECggIGAAIAO0YAA==.',
Pf='Pfchen:BAAANQADCgYICQAAAA==.',
Pi='Pippy:BAAANQAECgEIAQAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEIAwAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.Porimma:BAAANQADCgMIAwAAAA==.',
Pr='Prom:BAAANQADCgYICAAAAA==.Promethèus:BAABNQAECn8kAAIBAAoKxxkUSgDuAgABAAoKxxkUSgDuAgAAAA==.',
Pu='Puffypuff:BAAANQADCggICAAAAA==.',
Qo='Qoheleth:BAAANQAECgYICwAAAA==.',
Qu='Quanjo:BAAANQADCgUIBQAAAA==.Queedle:BAABNQAECn8hAAIfAAgKfguVAgAqAQAfAAgKfguVAgAqAQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDwAAAA==.',
Ra='Ragalstan:BAAANQADCgEIAQAAAA==.Rainlette:BAAANQAECgQIBQAAAA==.Rainsvoker:BAACNQAFFH8RAAIYAAYKDxLqAgDXAQAYAAYKDxLqAgDXAQA1AAQKf2cAAhgACgr2IG0AALcCABgACgr2IG0AALcCAAAA.Ramike:BAABNQAECn8lAAIRAAkKGBpiDQBcAgARAAkKGBpiDQBcAgAAAA==.Randal:BAAANQADCgEIAQAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCwAAAA==.Recovery:BAAANQAECgIIBAAAAA==.Reddan:BAAANQAECgQIDgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgoKMAAUAIYeAA==.Retman:BAAANQADCgEIAQAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDwAAAA==.Rinà:BAAANQAECgEIAQAAAA==.Rit:BAAANQAECgYIDAAAAA==.Ritzon:BAABNQAECn8iAAILAAoKHxiDSgCqAgALAAoKHxiDSgCqAgAAAA==.',
Ro='Robbert:BAAANQAECggICAAAAA==.Rosara:BAAANQAECggIEAAAAA==.',
Rr='Rrook:BAAANQADCgQIBgAAAA==.',
Ry='Ryanrainolds:BAAANQADCgQIBAABNQAECgcIHgAbAHYjAA==.Rykken:BAAANQAECgEIAQABNQAECgIIAgANAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Sacredjuice:BAAANQAECgEIAQAAAA==.Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcICAAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQAECgIIAgAAAA==.',
Sh='Shamalaya:BAAANQADCgUIBgAAAA==.Shamburgler:BAAANQAECgIIAwAAAA==.Shan:BAAANQAECgcIDwAAAA==.Sherrilu:BAAANQADCgIIAgAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAEANQADCgYIBwABNQAECgIIAwANAAAAAA==.',
Si='Sieya:BAAANQAECgEIAQAAAA==.Sinarria:BAAANQADCgUICAAAAA==.Sithra:BAAANQADCgQIBAAAAA==.',
Sk='Skitzop:BAAANQAECgQICAAAAA==.Skullace:BAAANQAECgUIEAAAAA==.Skylette:BAAANQADCggIDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.Slilith:BAAANQABCgIIAgAAAA==.',
Sn='Snakeblitzen:BAAANQADCgQIBAAAAA==.Snakeosham:BAAANQAECgUIBwAAAA==.Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgUIDgABNQAECgoKJQARAAYMAA==.Snoopingas:BAAANQADCgEIAwAAAA==.',
So='Soothingdusk:BAAANQAECgEIAQABNQADCgEIAgANAAAAAA==.Sortiebatoru:BAAANQAECgEIAQAAAA==.Soulblight:BAAANQADCggIDwAAAA==.',
Sp='Sparkplugg:BAAANQADCgQICAAAAA==.Sparthos:BAABNQAECn8XAAMYAAYKugVNJgAEAQAYAAYKugVNJgAEAQAgAAEKAABOJwAmAAAAAA==.Spideyrogue:BAAANQAECgEIAQAAAA==.Springbuck:BAAANQADCgEIAgAAAA==.',
Sr='Srfreaky:BAAANQAECgEIAQAAAA==.',
St='Stabatha:BAAANQAECgEIAQAAAA==.Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAABNQAECn8rAAIEAAkKhwekHAA1AQAEAAkKhwekHAA1AQAAAA==.Stocklock:BAAANQAECgEIAwAAAA==.Stormblessed:BAAANQADCgQIBAAAAA==.Stowned:BAAANQAECgQIBQAAAA==.Stumpyborg:BAAANQAECgEIAQABNQAECgUIEAANAAAAAA==.',
Su='Sune:BAAANQADCgUICQAAAA==.Suzuya:BAAANQADCgEIAQAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tamerlane:BAAANQADCgEIAQAAAA==.Tanlon:BAAANQAECgEIAQAAAA==.Tanthos:BAAANQADCgEIAQAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgoKJQARAAYMAA==.Tatari:BAAANQADCgYJCgABNQAECgUICwANAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Telandril:BAABNQAECn8iAAIhAAoKGhGAJgDuAQAhAAoKGhGAJgDuAQAAAA==.Tellanna:BAABNQAECn8bAAIBAAYKawKujACtAAABAAYKawKujACtAAAAAA==.Tensuken:BAAANQAECgUIEAAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgcIDAAAAA==.',
Th='Thadium:BAAANQADCgcIBwAAAA==.Thaet:BAAANQABCgUIBwAAAA==.That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgUIBAAAAA==.Thebran:BAAANQADCggJEgAAAA==.Thejuiciest:BAAANQAECgYICQAAAA==.Theunclepaul:BAAANQAECgUICgAAAA==.',
Ti='Tiarl:BAABNQAECn82AAIbAAoKIR42JgDSAgAbAAoKIR42JgDSAgAAAA==.Tinydots:BAAANQAECgUIDwAAAA==.Tinypaws:BAAANQADCgQIBAAAAA==.',
To='Tokamura:BAAANQADCgEIAQAAAA==.Tom:BAAANQADCgMIBQAAAA==.Tomoyá:BAAANQADCgYIBgAAAA==.Toniichopper:BAAANQAECgEJAQAAAA==.Tonn:BAAANQADCgUIDwAAAA==.Toosxyfohair:BAAANQAECgEIAQAAAA==.Torhal:BAAANQADCgIIAgAAAA==.',
Tr='Trimble:BAAANQABCggIBgAAAA==.',
Tt='Tt:BAAANQAFFAQIAwAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.Twylo:BAEANQAECggICAABNQAECggIJAAYADcjAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgQIBgAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAABNQAECn8VAAMPAAkKtSCHBgDHAQAPAAcKXyGHBgDHAQAEAAQK6h2oYgAZAQAAAA==.Unfriendly:BAAANQADCggIDAAAAA==.',
Va='Vaelora:BAAANQAECggIEAAAAA==.Valakk:BAAANQAECgUIDgAAAA==.Valandre:BAAANQADCgEIAQAAAA==.Valsitril:BAAANQAECgUIEgABNQAECgcIFwAWACgPAA==.Valwynn:BAAANQADCgEIAQAAAA==.Vanara:BAAANQADCgEIAwAAAA==.Varelyna:BAAANQADCgYICAABNQAECgcIFwAWACgPAA==.',
Ve='Velsetin:BAAANQAECgEIAQABNQAFFAMIAwANAAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Vexian:BAAANQADCgcIGgABNQAECgkJKgATABAZAA==.',
Vi='Vicas:BAAANQAECgQIAwAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBwAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Vo='Voidzzmid:BAAANQADCgIIAgAAAA==.',
Wa='Warded:BAAANQAECgIIAQAAAA==.',
We='Wesjenks:BAAANQAECgUICAAAAA==.',
Wh='Whisperlia:BAAANQAECgIIAgAAAA==.Whisperwindd:BAAANQAECgYICwAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQAECgIIBAAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECgUICwANAAAAAA==.',
Xa='Xandina:BAAANQADCgQICgAAAA==.Xanndor:BAAANQABCggICAAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQADCggIFAABNQAECgQICQANAAAAAA==.',
Ya='Yaerin:BAABNQAECn8eAAMbAAkK4R8+EgA3AwAbAAkK4R8+EgA3AwAeAAMK0Q79GgCQAAAAAA==.Yahman:BAAANQAECgQIBAABNQAECgoKKAABACIkAA==.Yaoi:BAABNQAECn8yAAMSAAoKdA7AlABUAQASAAgKhgjAlABUAQAdAAoKaQ19HABKAQAAAA==.',
Ye='Yevanendra:BAAANQADCgYICwAAAA==.',
Yo='Yokof:BAAANQAECgUIBQAAAA==.',
Ys='Yssuptaei:BAAANQADCgEIAQAAAA==.',
Yu='Yungfungi:BAAANQADCgcIGQAAAA==.Yuukon:BAABNQAECn8pAAIEAAkKXRB1PgDSAQAEAAkKXRB1PgDSAQAAAA==.',
Za='Zackman:BAAANQADCggIHAAAAA==.Zad:BAAANQAECgUIBAABNQAFFAUIDAAEAKcWAA==.Zaddydruid:BAAANQAECgYIBgABNQAFFAUIDAAEAKcWAA==.Zadira:BAACNQAFFH8MAAIEAAUKpxZFBwCHAQAEAAUKpxZFBwCHAQA1AAQKfzUAAwQACgqVH2IKAEcDAAQACQq2IWIKAEcDAAcABApgF3eLANMAAAAA.Zadirasham:BAABNQAECn8UAAIdAAgKqRs5SQBSAgAdAAgKqRs5SQBSAgABNQAFFAUIDAAEAKcWAA==.',
Ze='Zeeze:BAAANQADCgcIBwAAAA==.Zephrylia:BAAANQAECgEIAQAAAA==.',
Zu='Zuriel:BAAANQAECgQIEAAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgYICAAAAA==.',
['Àm']='Àmagezing:BAAANQAECgIIAgABNQAECgoKKAAKAFEjAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ös']='Östara:BAAANQAECgUICwAAAA==.',
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
