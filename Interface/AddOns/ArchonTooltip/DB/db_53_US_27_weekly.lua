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

local lookup = {'Mage-Arcane','Druid-Guardian','Hunter-Survival','DeathKnight-Frost','Priest-Shadow','Paladin-Retribution','Shaman-Elemental','Warlock-Demonology','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Mage-Frost','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Warrior-Protection','Shaman-Restoration','Rogue-Subtlety','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Devastation','Druid-Balance','Warrior-Fury','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Monk-Windwalker','Druid-Feral','Priest-Discipline','Evoker-Augmentation','Druid-Restoration',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaravos:BAAANQAECgYIBgAAAA==.Aatrøx:BAAANQAECgcIEAAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQAECgUIBAAAAA==.Adura:BAAANQADCggICwAAAA==.',
Ae='Aeirith:BAABNQAECn8kAAIBAAoK4hUkjwBhAgABAAoK4hUkjwBhAgAAAA==.',
Ai='Ailsà:BAAANQADCgIIAgABNQAECgYIGwACAOkRAA==.Airius:BAAANQAECgEIAQAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMIAwAAAA==.',
Am='Amalthia:BAAANQAECgcIDQAAAA==.Amarasu:BAABNQAECn8fAAIDAAcK9BHpBwDlAQADAAcK9BHpBwDlAQAAAA==.Amarlly:BAABNQAECn8fAAIEAAgKHRBKMQBfAQAEAAgKHRBKMQBfAQAAAA==.',
An='Ancelina:BAABNQAECn8ZAAIFAAcKRB4SEwCZAQAFAAcKRB4SEwCZAQAAAA==.Anderton:BAABNQAECn81AAIGAAgK9BC1hgBDAQAGAAgK9BC1hgBDAQAAAA==.Andilocks:BAAANQADCggILgAAAA==.Anditracks:BAAANQADCggIIQAAAA==.Andraenei:BAABNQAECn8aAAIHAAYKUA52pQBJAQAHAAYKUA52pQBJAQAAAA==.Andrela:BAAANQAECgEIAQAAAA==.Andromadda:BAAANQADCgcIBwAAAA==.Aneira:BAABNQAECn8bAAICAAYK6RGeIgD0AAACAAYK6RGeIgD0AAAAAA==.',
Ap='Applefritter:BAAANQADCggIDQABNQAECggIIwAIAKAaAA==.',
Aq='Aquarius:BAAANQADCgcIBwAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECn8/AAIJAAoKmyMRCgBkAwAJAAoKmyMRCgBkAwAAAA==.Archmedies:BAAANQADCgEIAQAAAA==.Archérhiro:BAACNQAFFH8WAAMKAAYKExvuBwDNAQAKAAYKExvuBwDNAQALAAEKAAAfKAA1AAA1AAQKf0IAAwoACgoRJNUFADMDAAoACgoRJNUFADMDAAsABQpTEANFADEBAAAA.Arillann:BAABNQAECn8sAAIMAAoKqCDaBwAjAwAMAAoKqCDaBwAjAwAAAA==.Arin:BAAANQAECgQIBgABNQAECgoKHQANAP4WAA==.Arms:BAAANQAECgQIBgABNQAECgoKKQAGAPMWAA==.Arrook:BAAANQAECgEIAQAAAA==.Artdemsamis:BAABNQAECn8ZAAQOAAoKAhEWNgDpAAAIAAgKxA+ymACpAQAOAAQKqw4WNgDpAAAPAAEKAADNIAAAAAAAAA==.Arttimar:BAAANQAECggICAAAAA==.Arvena:BAAANQADCgQIBAAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgAQAAAAAA==.Ashylock:BAABNQAECn8fAAIIAAoKlBTKUQBgAgAIAAoKlBTKUQBgAgABNQAFFAUIEwABAFUbAA==.Ashymage:BAACNQAFFH8TAAIBAAUKVRsXDwAZAQABAAUKVRsXDwAZAQA1AAQKf0EAAwEACgoDJcgWAHgDAAEACgoDJcgWAHgDABEAAQrTCu1GADYAAAAA.Askevar:BAABNQAECn8cAAISAAcKYwg8NgDnAAASAAcKYwg8NgDnAAAAAA==.Asriél:BAABNQAECn8ZAAIKAAkKtBn1YwBNAgAKAAkKtBn1YwBNAgAAAA==.Assoul:BAAANQABCgIIBAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQAECgIIAwABNQAFFAUIDwATAA8RAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.Atreus:BAABNQAECn8bAAIGAAkKGgOi1AC8AAAGAAkKGgOi1AC8AAAAAA==.',
Az='Azaleah:BAABNQAECn8vAAIGAAoKshCJegA2AgAGAAoKshCJegA2AgAAAA==.Azlan:BAAANQAECgEIAQAAAA==.Azraesha:BAABNQAECn8jAAIUAAoKyhAkFQCdAQAUAAoKyhAkFQCdAQAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Ba='Backy:BAAANQAECgUIBAAAAA==.',
Be='Beareold:BAAANQAECgEIAgAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQIDQAAAA==.Bigmon:BAABNQAECn9RAAMNAAoKuSFsIQAyAwANAAoKuSFsIQAyAwAVAAEKgA/SRAAvAAAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgQIBgAAAA==.Blackstaff:BAAANQADCggIEQAAAA==.Blessthefall:BAAANQAECggICQAAAA==.Bloodygrundl:BAABNQAECn8qAAIJAAoK4yBVEAAqAwAJAAoK4yBVEAAqAwAAAA==.Bluestorm:BAAANQAECgYIDwAAAA==.',
Bo='Bonegrinda:BAABNQAECn8nAAISAAgKdx6rMgBhAgASAAgKdx6rMgBhAgAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwAQAAAAAA==.',
Br='Branwynn:BAAANQAECgIIAQAAAA==.Bringg:BAAANQAECgQIBAAAAA==.',
Bu='Budgetcuts:BAAANQADCgYIBgAAAA==.Bulldoza:BAAANQADCgQIBAAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgEIAgAAAA==.Calliaa:BAAANQADCgYIBgAAAA==.Callmemommy:BAAANQAECgMIBAAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAABNQAECn8WAAINAAoKYgSflADkAAANAAoKYgSflADkAAAAAA==.Ceri:BAAANQAECggICQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFH8YAAIWAAcK1h8LBABFAgAWAAcK1h8LBABFAgA1AAQKfysAAhYACgo0JfQIAHoDABYACgo0JfQIAHoDAAAA.Chantix:BAAANQADCgYIBwAAAA==.Chaosshadow:BAABNQAECn8gAAIFAAgKxxFvFgBqAQAFAAgKxxFvFgBqAQAAAA==.Chaosti:BAABNQAECn8WAAISAAkKlwp2bABhAQASAAkKlwp2bABhAQAAAA==.Cheekymonkey:BAABNQAECn8nAAIBAAkKOQq3mwANAQABAAkKOQq3mwANAQAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Chueyé:BAAANQADCgUIBQABNQAECgoKOAAXAHIgAA==.Chune:BAAANQADCgEIAQAAAA==.Churros:BAAANQAECgcICQABNQAECggIIwAIAKAaAA==.',
Co='Cobiepaladin:BAAANQAECgYIBgAAAA==.Coconuts:BAAANQAECgEIAQAAAA==.Conqueefador:BAAANQAECgIIAgAAAA==.Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAABNQAECn8mAAIYAAYKtR2ecwC9AQAYAAYKtR2ecwC9AQAAAA==.Crosslock:BAAANQADCgcICwAAAA==.',
Cu='Cuack:BAAANQAECgEIAQAAAA==.',
Cy='Cynnari:BAABNQAECn8iAAIIAAcKrAd/wABLAQAIAAcKrAd/wABLAQAAAA==.',
Da='Dagnabit:BAAANQADCggIGwAAAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAABNQAECn8fAAIZAAgKpw9gLQA1AQAZAAgKpw9gLQA1AQAAAA==.Darkpriestes:BAAANQADCgQIBAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgUIDwAAAA==.Dartian:BAAANQAECgMJAwABNQAECgcIGgAKAM4LAA==.',
De='Deathmare:BAABNQAECn8XAAMZAAkKpguwIACQAQAZAAkKTAuwIACQAQAaAAQKdAf6IQCzAAAAAA==.Deathty:BAAANQAECgYIBgABNQAECgoKHQAKAF8UAA==.Deeptroat:BAAANQADCgEIAQABNQAECgcIHwADAPQRAA==.Dementia:BAAANQADCgcIBwAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAABNQAECn8sAAMIAAgK0BPqdQAAAgAIAAgK0BPqdQAAAgAPAAEKAAAfMQAzAAAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAABNQAECn8VAAQEAAUKiA/UbwDfAAAEAAQKQw/UbwDfAAASAAIKtQRBzABUAAAJAAEK0g1PywAzAAAAAA==.Diltlish:BAAANQAECgQICAAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAABNQAECn8nAAINAAkKYBslfwAdAgANAAkKYBslfwAdAgAAAA==.',
Dm='Dmginc:BAAANQAECgQICgAAAA==.',
Do='Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgQIBAAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Drackonia:BAAANQAECgUIDgAAAA==.Dracolyte:BAAANQADCgEIAQAAAA==.Dragonflai:BAABNQAECn8nAAIBAAoKixAznwBDAgABAAoKixAznwBDAgAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQAECgUICAAAAA==.Drakkei:BAABNQAECn8uAAIKAAoKORUsRgDMAQAKAAoKORUsRgDMAQABNQAECgoKNgACADgSAA==.Drshortbus:BAAANQAECgUICQAAAA==.Drunkenfist:BAAANQAECgQIBQAAAA==.Drylo:BAEBNQAECn8qAAIbAAkK9R8oBgAqAwAbAAkK9R8oBgAqAwAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
El='Elarol:BAAANQADCgYICQAAAA==.Eleonore:BAAANQAECgYIDQAAAA==.Elfie:BAAANQADCgYIBgAAAA==.Elray:BAAANQAECgUIBwAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECgcICQAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
Er='Erf:BAAANQADCgYIDgAAAA==.Erfinden:BAAANQADCgIIBAAAAA==.',
Es='Espers:BAABNQAECn8lAAIcAAgKrw5qSwC3AQAcAAgKrw5qSwC3AQAAAA==.',
Et='Ethellin:BAABNQAECn8nAAIGAAgK5QTRBQEVAQAGAAgK5QTRBQEVAQAAAA==.',
Eu='Euph:BAAANQAECgYICwAAAA==.',
Ev='Evilhearts:BAAANQADCggICAAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgYIEgABNQAECgoKNQAGAEMmAA==.Feedmepizzas:BAAANQAECgEIBAAAAA==.Feildmedic:BAAANQAECgUIBwABNQAECgUIEAAQAAAAAA==.Feleria:BAAANQAECgEIAQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQAECgIIAgAAAA==.Fizzysoda:BAAANQADCgcIBwAAAA==.',
Fl='Fluxarata:BAABNQAECn8aAAIUAAcK4gehQgA6AQAUAAcK4gehQgA6AQAAAA==.',
Fr='Fred:BAABNQAECn8UAAIdAAYK9QZDFACqAAAdAAYK9QZDFACqAAAAAA==.Friendly:BAABNQAECn8xAAMeAAoK2SSkAgDqAgAeAAoKeySkAgDqAgAXAAUKFyHwNgCNAQAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgUICQAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.Fupacabra:BAAANQADCgcIBwAAAA==.Fuzzyhunter:BAAANQADCgcIEQAAAA==.',
['Fï']='Fïzzle:BAAANQAECgQIBQABNQAECgYIGwACAOkRAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAABNQAECn8nAAIKAAoK1BnFPwCrAgAKAAoK1BnFPwCrAgAAAA==.Gagageoff:BAAANQAECgEIAQAAAA==.Gardyson:BAABNQAECn8pAAMVAAoKTAwfIABOAQANAAoKpAgcsQCiAQAVAAgK0A0fIABOAQAAAA==.Garwarmegad:BAAANQAECgQIBQAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Gl='Gloney:BAAANQADCgMIAwAAAA==.',
Gn='Gnomew:BAAANQAECgMIAwAAAA==.',
Go='Gobsprocket:BAAANQADCggICAAAAA==.Gojira:BAAANQABCgUIBgAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAABNQAECn8wAAILAAoKlRKpEgCXAQALAAoKlRKpEgCXAQAAAA==.Grenadeout:BAABNQAECn8UAAQXAAgKthsQKgDaAQAXAAgKthsQKgDaAQAeAAMKahY8cwDkAAAfAAEKAAB1GQBNAAAAAA==.Grimaldus:BAAANQAECgIIAQABNQAECgYICAAQAAAAAA==.',
Ha='Harrod:BAAANQADCgYIBgAAAA==.Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQAQAAAAAA==.',
He='Hefty:BAAANQAECgUIEAAAAA==.Hellbad:BAABNQAECn8WAAMgAAgKAhdbDQAlAgAgAAgKAhdbDQAlAgAhAAYK4ADnbQAuAAAAAA==.Hellsspawn:BAAANQADCgUIDAAAAA==.',
Ho='Hokàge:BAABNQAECn84AAMXAAoKciApEwCKAgAXAAoKpB8pEwCKAgAeAAcKLBwXLAA4AgAAAA==.Holyprom:BAAANQADCgUIBQAAAA==.Homealone:BAAANQAECggIEQAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huey:BAAANQAECgQIBAABNQAECgkJHgAFACIRAA==.Huntinfuzzy:BAABNQAECn8bAAIKAAgKjwnktACaAQAKAAgKjwnktACaAQAAAA==.Huugg:BAAANQAECgQIBAAAAA==.',
Hy='Hymncarrey:BAABNQAECn8kAAITAAcK/COfLAC2AgATAAcK/COfLAC2AgAAAA==.Hynkie:BAABNQAECn8aAAITAAkKQxLmLQAMAgATAAkKQxLmLQAMAgAAAA==.',
Id='Idari:BAAANQABCgEIAQAAAA==.',
Ig='Igothots:BAAANQAECgYICgABNQAECggIEQAQAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAABNQAECn8rAAQPAAkKPhxjAgA3AgAPAAkKPhxjAgA3AgAIAAYKXA5dtgBiAQAOAAEK4wZnfwAtAAAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQAECgcIHwADAPQRAA==.',
Ja='Jackyll:BAAANQAECggIBwAAAA==.Jatix:BAABNQAECn8aAAIGAAkKThjsbgBSAgAGAAkKThjsbgBSAgAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgQIBQAQAAAAAA==.',
Je='Jellytown:BAABNQAECn8pAAIRAAoKuhiMBQC3AgARAAoKuhiMBQC3AgAAAA==.Jelorinea:BAAANQADCgYIBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgQICQAAAA==.',
Ju='Juicylucy:BAAANQAECgEIAQAAAA==.Jundra:BAAANQADCgYICAAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQADCggIHgAAAA==.Justine:BAAANQAECgMIAwAAAA==.',
['Jô']='Jôhnwick:BAABNQAECn8dAAILAAkKZw4UKwDyAQALAAkKZw4UKwDyAQAAAA==.',
Ka='Kaedas:BAAANQADCgMIAwABNQAECgoKNgACADgSAA==.Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAABNQAECn8pAAIKAAoK5BK7UgB4AgAKAAoK5BK7UgB4AgAAAA==.Kaladil:BAAANQAECgQIBAAAAA==.Kamaren:BAAANQAECgIIAgAAAA==.Kashmir:BAAANQAECgMIAwAAAA==.Kawdor:BAAANQAECgQIBwAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Ke='Kelaino:BAAANQABCgYIBgAAAA==.',
Kh='Khota:BAAANQAECggICwAAAA==.',
Ki='Killanick:BAAANQAECgUIBAAAAA==.',
Ko='Koldfront:BAAANQADCgYIDgAAAA==.Kollinator:BAAANQAECgcICgAAAA==.',
Ku='Kurtina:BAABNQAECn8wAAINAAoKmRP8QQDHAQANAAoKmRP8QQDHAQAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAABNQAECn8dAAIKAAoKXxS1UQB7AgAKAAoKXxS1UQB7AgAAAA==.Larac:BAAANQAECggIDQAAAA==.',
Le='Leddy:BAAANQADCgUICQAAAA==.Leif:BAABNQAECn8oAAIbAAoKdxVhBwCmAQAbAAoKdxVhBwCmAQAAAA==.Lemmart:BAABNQAECn8WAAIPAAgK7Qw5CAAnAQAPAAgK7Qw5CAAnAQAAAA==.Lenik:BAAANQAECgYIEQAAAA==.',
Li='Licorice:BAABNQAECn8jAAMIAAgKoBqSTwB1AQAIAAgKoBqSTwB1AQAOAAEKEwvQewAxAAAAAA==.Lieree:BAABNQAECn8hAAIBAAgK/gn63gDKAQABAAgK/gn63gDKAQAAAA==.Lilyfaye:BAAANQADCgEIAQAAAA==.Limosfire:BAAANQAECgUIBwAAAA==.',
Lo='Lockty:BAABNQAECn8cAAIIAAoKjxBPNwDNAQAIAAoKjxBPNwDNAQABNQAECgoKHQAKAF8UAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.Lorian:BAAANQAECgUIBQAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAEANQAECgIIAwAAAA==.Lucity:BAAANQAECgcIDwABNQAECgkJGgAGAE4YAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQADCgYIDgAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQAQAAAAAA==.Lunà:BAAANQAECgQICQAAAA==.',
Ly='Lystral:BAAANQAECgQICQAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUIDgAAAA==.',
['Lá']='Lásh:BAAANQAECgYICwABNQAECgYIGwACAOkRAA==.',
Ma='Mace:BAABNQAECn8fAAIGAAkKpyLRHgBIAwAGAAkKpyLRHgBIAwAAAA==.Magdalena:BAAANQAECgQIBQAAAA==.Mageyboi:BAAANQAECgMIAgABNQAECgoKOAAXAHIgAA==.Magickul:BAAANQAECgQIBwAAAA==.Mahano:BAAANQAECgEIAQABNQAECgoKKQAVAEwMAA==.Malìficus:BAAANQADCgcIBwAAAA==.Manadâr:BAAANQAECgUIBgAAAA==.Marinas:BAAANQADCgcIFgAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgMIBQAAAA==.Mazumaragg:BAAANQAECgQICAABNQAECgoKKQAVAEwMAA==.',
Me='Mello:BAAANQADCgUIBQAAAA==.',
Mi='Miande:BAAANQAECgYICgAAAA==.Microburst:BAABNQAECn8rAAIHAAoKYgfURgA7AQAHAAoKYgfURgA7AQAAAA==.Minilock:BAABNQAECn8jAAQIAAkKIQqwYgA+AQAIAAkKIQqwYgA+AQAOAAMKwgHqYQBhAAAPAAEKDAcpMgAwAAAAAA==.Missdeeds:BAAANQABCgQIBAAAAA==.Missleading:BAAANQABCgEIAQAAAA==.Miyagifu:BAAANQADCgMJBAABNQAECgUIEAAQAAAAAA==.Mièlikki:BAABNQAECn8YAAICAAcK8hjVGQA9AQACAAcK8hjVGQA9AQAAAA==.',
Mo='Modelotime:BAAANQADCggICwAAAA==.Modsagoodtnk:BAAANQADCggICQABNQAECgEIAQAQAAAAAA==.Mongermook:BAABNQAECn8aAAMCAAgKRg2nKABRAQACAAgKRg2nKABRAQAiAAEK4QgCMQAyAAAAAA==.Monnkysham:BAAANQAECgIIAgAAAA==.Mooglefur:BAAANQADCgcICAAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAABNQAECn8kAAIWAAgKTheuQgCMAQAWAAgKTheuQgCMAQAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECgYICQAAAA==.Nauseous:BAAANQADCggJCAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Nexedo:BAAANQAECgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBgAAAA==.Nickelodeon:BAAANQAECgQICQAAAA==.Nickita:BAAANQAECgQIBgAAAA==.Nicky:BAAANQAECgEIAQAAAA==.Nightgear:BAACNQAFFH8WAAIKAAcKHRHfAwAhAgAKAAcKHRHfAwAhAgA1AAQKf1gAAgoACgonItQNAOACAAoACgonItQNAOACAAAA.Nighti:BAAANQADCgQIBAAAAA==.Niteshadeth:BAAANQADCgMIAwAAAA==.Nixeava:BAAANQAECgQIDwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAABNQAECn82AAMCAAoKOBJtFwD3AQACAAgKvBZtFwD3AQAcAAgK6wevZwAuAQAAAA==.',
Od='Ode:BAABNQAECn8qAAIBAAkKRAxkXQCVAQABAAkKRAxkXQCVAQAAAA==.Odex:BAAANQAECgYIEgAAAA==.',
On='Onlymages:BAABNQAECn8nAAIBAAcKhwuCpQD8AAABAAcKhwuCpQD8AAAAAA==.Onos:BAAANQAECgQICwAAAA==.',
Or='Orinin:BAABNQAECn8eAAMFAAkKIhFpLQC6AQAFAAkKIhFpLQC6AQAjAAMKhgtAGwCOAAAAAA==.',
Ou='Outdeath:BAAANQAECgMIAwABNQAECgYIDwAQAAAAAA==.Outkíll:BAAANQAECgYIDwAAAA==.',
Pa='Pally:BAABNQAECn8pAAIGAAoK8xbOOAAWAgAGAAoK8xbOOAAWAgAAAA==.Pandarweb:BAAANQAECgUIBgAAAA==.Papasmurfz:BAAANQAECgUIBAAAAA==.Pathogen:BAABNQAECn8qAAISAAoKJiPqCQBuAwASAAoKJiPqCQBuAwAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAABNQAECn8kAAIEAAgKhBIYLgBwAQAEAAgKhBIYLgBwAQAAAA==.Perve:BAAANQAECggIEQABNQAECgkJGQAKALQZAA==.',
Pf='Pfchen:BAAANQADCgYIBwAAAA==.',
Pi='Pippy:BAAANQAECgIIAQAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEIAwAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.',
Pr='Prom:BAAANQADCggIEQAAAA==.Promethèus:BAABNQAECn8kAAIBAAoKxxkUSgDuAgABAAoKxxkUSgDuAgAAAA==.',
Pu='Puffypuff:BAAANQADCggICAAAAA==.',
Qo='Qoheleth:BAAANQAECgYICwAAAA==.',
Qu='Quanjo:BAAANQADCgUIBQAAAA==.Queedle:BAABNQAECn8mAAIfAAkKjgsiAwBnAQAfAAkKjgsiAwBnAQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggJDAAAAA==.Rainlette:BAAANQAECgQIBQAAAA==.Rainsvoker:BAACNQAFFH8SAAIbAAcK/RDqAgDXAQAbAAcK/RDqAgDXAQA1AAQKf3EAAhsACgqAITIDAHcDABsACgqAITIDAHcDAAAA.Ramike:BAABNQAECn8qAAIVAAkKjBpiDQBcAgAVAAkKjBpiDQBcAgAAAA==.Randal:BAAANQABCgQIBAAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCQAAAA==.Recovery:BAAANQAECgIIAwAAAA==.Reddan:BAAANQAECgQIDgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgoKOAAXAHIgAA==.Retman:BAAANQABCgIIAgAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rinà:BAAANQAECgEIAQAAAA==.Rit:BAAANQAECgYIDAAAAA==.Ritzon:BAABNQAECn8pAAINAAoKTBmDSgCqAgANAAoKTBmDSgCqAgAAAA==.',
Ro='Robbert:BAAANQAECggICAAAAA==.Rosara:BAABNQAECn8WAAIYAAkKBhEFJwAXAgAYAAkKBhEFJwAXAgAAAA==.',
Rr='Rrook:BAAANQADCgQICAAAAA==.',
Ry='Ryanrainolds:BAAANQADCgQIBAABNQAECgcIJAATAPwjAA==.Rykken:BAAANQAECgEIAQABNQAECgIIAgAQAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Sakúra:BAAANQAECgQIBAAAAA==.Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQAECgQIBAAAAA==.',
Sh='Shamalaya:BAAANQADCgUIBgAAAA==.Shamburgler:BAAANQAECgUIBwAAAA==.Shan:BAAANQAECgcIDwAAAA==.Sherrilu:BAAANQADCgIIAgAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAEANQADCgYIBgABNQAECgIIAwAQAAAAAA==.',
Si='Sinarria:BAAANQADCgUICAAAAA==.Sithra:BAAANQADCgQIBAAAAA==.',
Sk='Skitzop:BAAANQAECgQICAAAAA==.Skullace:BAABNQAECn8ZAAIIAAgKUAXoiADgAAAIAAgKUAXoiADgAAAAAA==.Skylette:BAAANQADCggIDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.Slilith:BAAANQABCgIIAgAAAA==.',
Sn='Snakeblitzen:BAAANQADCgQIBAAAAA==.Snakeosham:BAAANQAECgYICQAAAA==.Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgUIDgABNQAECgoKKQAVAEwMAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.Sortiebatoru:BAAANQAECgEIAQAAAA==.Soulblight:BAAANQADCggIFwAAAA==.',
Sp='Sparkplugg:BAAANQADCgQICAAAAA==.Sparthos:BAABNQAECn8XAAMbAAYKugVNJgAEAQAbAAYKugVNJgAEAQAkAAEKAABOJwAmAAAAAA==.Spideyrogue:BAAANQAECgEIAQAAAA==.Springbuck:BAAANQABCgIIAgAAAA==.',
Sr='Srfreaky:BAAANQADCggIHAAAAA==.',
St='Stabatha:BAAANQAECgEIAQAAAA==.Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAABNQAECn8sAAIEAAoKPwfpOAA3AQAEAAoKPwfpOAA3AQAAAA==.Stocklock:BAAANQAECgQIBAAAAA==.Stormblessed:BAAANQADCgQIBAAAAA==.Stowned:BAAANQAECgQIBQAAAA==.Stumpyborg:BAAANQAECgEIAQABNQAECgUIEAAQAAAAAA==.',
Su='Sune:BAAANQADCgUICQAAAA==.Suzuya:BAAANQABCggICgAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgoKKQAVAEwMAA==.Tatari:BAAANQADCgYJCgABNQAECgYICgAQAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Tel:BAAANQADCgQIAwAAAA==.Telandril:BAABNQAECn8pAAIlAAoKOhGAJgDuAQAlAAoKOhGAJgDuAQAAAA==.Tellanna:BAABNQAECn8dAAIBAAgKiAJ+yQC5AAABAAgKiAJ+yQC5AAAAAA==.Tensuken:BAABNQAECn8VAAIGAAcK3RXhxgCOAQAGAAcK3RXhxgCOAQAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgUIDgAAAA==.',
Th='Thadium:BAAANQADCgcIBwAAAA==.Thaet:BAAANQABCgUIBwAAAA==.That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgUIBAAAAA==.Thebran:BAAANQADCggJEAAAAA==.Thejuiciest:BAAANQAECgYICwAAAA==.Theunclepaul:BAAANQAECgUICgAAAA==.',
Ti='Tiarl:BAABNQAECn9AAAMTAAoKPR82JgDSAgATAAoKPR82JgDSAgAFAAMKtA3VOABpAAAAAA==.Tinydots:BAAANQAECgYIEgAAAA==.Tinypaws:BAAANQADCgUIBwAAAA==.',
To='Tom:BAAANQADCgMIBAAAAA==.Tomoyá:BAAANQADCgYIBgAAAA==.Toniichopper:BAAANQAECgEJAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQAECgEIAQAAAA==.Torhal:BAAANQADCgIIAgAAAA==.',
Tr='Trimble:BAAANQABCggIBgAAAA==.',
Tt='Tt:BAAANQAFFAQIAwAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.Twylo:BAEANQAECggICAABNQAECgkJKgAbAPUfAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgQIBgAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAABNQAECn8ZAAMSAAkK7iDPGQCoAQASAAcKoSHPGQCoAQAEAAQK6h2oYgAZAQAAAA==.Unfriendly:BAAANQADCggIDAAAAA==.',
Va='Vaelora:BAABNQAECn8WAAIJAAkK+BD5HgCaAQAJAAkK+BD5HgCaAQAAAA==.Valakk:BAAANQAECgUIEQAAAA==.Valsitril:BAAANQAECgUIEgABNQAECggIHwAZAKcPAA==.Vanara:BAAANQABCggIDQAAAA==.Varelyna:BAAANQADCgYIBgABNQAECggIHwAZAKcPAA==.',
Ve='Velsetin:BAAANQAECgEIAQABNQAFFAMIAwAQAAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Vexian:BAAANQADCgcIGQABNQAECgkJMgAFAOcaAA==.',
Vi='Vicas:BAAANQAECgUICAAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Vo='Voidzzmid:BAAANQADCgIIAgAAAA==.',
Wa='Warded:BAAANQAECgIIAQAAAA==.',
We='Webgar:BAAANQADCgYIBgAAAA==.Wesjenks:BAAANQAECgUICAAAAA==.',
Wh='Whisperlia:BAAANQAECgIIAgAAAA==.Whisperwindd:BAAANQAECgUIDwAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQAECgEIAwAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECgYICgAQAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.Xanndor:BAAANQABCggICAAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQAECgMIAwABNQAECgQICQAQAAAAAA==.',
Ya='Yaerin:BAABNQAECn8iAAMTAAoKjR4+EgA3AwATAAoKjR4+EgA3AwAjAAMK0Q79GgCQAAAAAA==.Yahman:BAAANQAECgQIBAABNQAECgoKKAABACIkAA==.Yaoi:BAABNQAECn82AAMHAAoKkg2QPQBeAQAHAAoKkg2QPQBeAQAWAAgK0wjAlABUAQAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQAECggIBQAAAA==.',
Yu='Yungblood:BAAANQAECgEIAgAAAA==.Yungfungi:BAAANQADCgcIGQAAAA==.Yuukon:BAABNQAECn8rAAIEAAkKXRB1PgDSAQAEAAkKXRB1PgDSAQAAAA==.',
Za='Zackman:BAAANQADCggIHAAAAA==.Zad:BAAANQAECgUIBAABNQAFFAUIDAAEAKcWAA==.Zaddydruid:BAAANQAECgYIBgABNQAFFAUIDAAEAKcWAA==.Zadira:BAACNQAFFH8MAAIEAAUKpxZFBwCHAQAEAAUKpxZFBwCHAQA1AAQKfzoAAwQACgpcIWIKAEcDAAQACgpcIWIKAEcDAAkABApgF3eLANMAAAAA.Zadirasham:BAABNQAECn8cAAIHAAkKwB63HgAGAgAHAAkKwB63HgAGAgABNQAFFAUIDAAEAKcWAA==.Zadorca:BAAANQAECgUIBQABNQAFFAUIDAAEAKcWAA==.',
Ze='Zeeze:BAAANQADCgcIBwAAAA==.',
Zu='Zuriel:BAAANQAECgQIEwAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgYICwAAAA==.',
['Àm']='Àmagezing:BAAANQAECgIIAgABNQAECgoKLQAMANUjAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ða']='Ðark:BAAANQADCggICAAAAA==.',
['Ös']='Östara:BAAANQAECgYICgAAAA==.',
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
