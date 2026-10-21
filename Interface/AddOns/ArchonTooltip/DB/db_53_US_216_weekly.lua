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

local lookup = {'Mage-Arcane','Mage-Frost','Monk-Brewmaster','Shaman-Enhancement','DeathKnight-Blood','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Priest-Shadow','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warrior-Protection','Paladin-Holy','Priest-Discipline','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Outlaw','Paladin-Protection','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=53,date='2026-10-20',data={Ag='Aggressíon:BAABNQAECn8gAAMBAAkKvRnyIQCLAQABAAgK9BjyIQCLAQACAAIKCyB6DQC0AAAAAA==.',
Ai='Airen:BAAANQAECgMIAgAAAA==.',
Al='Allywafflez:BAAANQAECgIIAgAAAA==.Alphadots:BAAANQAECgQIBAAAAA==.',
An='Anarsonista:BAAANQAECgQIDAAAAA==.',
Ap='Apachaler:BAABNQAECn8sAAIDAAoKHxtfAgCmAQADAAoKHxtfAgCmAQAAAA==.Appoc:BAAANQAECgQIDgAAAA==.',
Ar='Arathael:BAAANQABCgIIAgAAAA==.Araun:BAAANQADCgYIDAAAAA==.',
As='Asian:BAAANQAECgcIDQAAAA==.',
At='Atzula:BAAANQAECgUIBgAAAA==.',
Az='Azriel:BAAANQADCgIIAwAAAA==.',
Ba='Babyshamz:BAAANQAECgUIDwAAAA==.Babyzen:BAAANQADCggIHAAAAA==.Barca:BAAANQABCgEJAQAAAA==.Barranphalnx:BAABNQAECn8XAAIEAAgKBBkmCQBhAQAEAAgKBBkmCQBhAQAAAA==.',
Be='Bearorrist:BAAANQAECgcIBwABNQAFFAYIFQAFAFcaAA==.Beefydomo:BAAANQADCgYIDwABNQAECgQIBAAGAAAAAA==.Betsy:BAAANQAECgQIBwAAAA==.',
Bi='Bigboybek:BAAANQAECgIIBAAAAA==.',
Bl='Blackgarden:BAAANQAECgYICgAAAA==.',
Bo='Bojanglez:BAAANQABCgIIAgAAAA==.',
Bu='Built:BAABNQAECn8bAAQHAAkKXxxQSQCRAgAHAAgK7h5QSQCRAgAIAAMKdA/YXgCrAAAJAAIKCQ0/EAB4AAAAAA==.Bulshight:BAAANQAECgQIAwAAAA==.Buschlight:BAAANQADCgEIAQAAAA==.',
Ca='Cabbage:BAAANQAECgIIAQAAAA==.Carbonara:BAAANQAECgQIBAAAAA==.',
Ce='Celedor:BAAANQADCgYIBgABNQAFFAUIDQAKANgZAA==.',
Ch='Chaos:BAABNQAECn8wAAMJAAkKaCRmAACJAgAJAAkKaCRmAACJAgAHAAQKnCQe3wBDAQABNQAECgoKHgALAIwWAA==.Chaosfu:BAABNQAECn8eAAILAAoKjBbICQB0AQALAAoKjBbICQB0AQAAAA==.Chimatsuri:BAACNQAFFH8SAAILAAcKaxR6BAD+AQALAAcKaxR6BAD+AQA1AAQKfzIAAgsACgo6IAYQAOYCAAsACgo6IAYQAOYCAAAA.Choal:BAAANQADCgIIAgAAAA==.',
Cl='Clawreece:BAAANQABCggIGgAAAA==.Clyde:BAAANQADCggICAAAAA==.',
Co='Conta:BAAANQADCgYIBgAAAA==.',
Cu='Cuchicu:BAABNQAECn86AAMMAAoKCR74CwAMAwAMAAoKCR74CwAMAwANAAIKXhBlUAA3AAAAAA==.',
Da='Damagexx:BAAANQADCgYIBgAAAA==.',
De='Deladre:BAEANQAECggIEAAAAA==.Desim:BAAANQABCgQIBAAAAA==.Dez:BAAANQAECgUIDwAAAA==.',
Di='Diaperbaby:BAABNQAECn8cAAIOAAkK9RXsQwBcAgAOAAkK9RXsQwBcAgAAAA==.',
Dk='Dkamp:BAAANQADCgcIIAAAAA==.',
Do='Dokken:BAAANQAECgIIAgAAAA==.',
Dr='Dragondie:BAAANQADCgYIBgABNQADCgYIBgAGAAAAAA==.Drdot:BAAANQAECgMIAwAAAA==.Drewcifer:BAACNQAFFH8UAAMPAAcK7xtXBQAEAgAPAAcK7xtXBQAEAgAQAAEKtQtsFgBAAAA1AAQKfyQAAw8ACQopIy8hAJICAA8ACQpJHy8hAJICABAACAp/HDkgAEwCAAAA.Drewwar:BAAANQADCggICAABNQAFFAcIFAAPAO8bAA==.',
['Dü']='Düsk:BAAANQADCgcIDAAAAA==.',
Eh='Ehato:BAAANQADCgQIBAABNQADCgYIBgAGAAAAAA==.',
El='Eldrianne:BAAANQAECgUIBQABNQAECgUIBgAGAAAAAA==.Ellie:BAAANQAECgEIAQAAAA==.',
Eu='Eurekuh:BAAANQADCgYIBwAAAA==.',
Fh='Fhephok:BAAANQADCgEIAQAAAA==.',
Fl='Floral:BAABNQAECn8bAAINAAgK5A3xIwDXAAANAAgK5A3xIwDXAAAAAA==.',
Fo='Fomo:BAAANQADCgIIAgAAAA==.',
Fr='Francis:BAAANQADCgEIAQAAAA==.',
Ga='Galbsadi:BAABNQAECn8iAAIRAAcKUhGHmQCnAQARAAcKUhGHmQCnAQAAAA==.Garra:BAAANQABCgUIBQAAAA==.',
Gl='Gladdie:BAACNQAFFH8dAAIFAAYKQByMBwDrAQAFAAYKQByMBwDrAQA1AAQKfzgAAgUACgrPHSEPADYDAAUACgrPHSEPADYDAAAA.',
Go='Gormon:BAAANQAECgEIAQAAAA==.',
Gr='Graf:BAACNQAFFH8aAAISAAYKLiKIAABRAgASAAYKLiKIAABRAgA1AAQKfyoAAhIACQqEJsYAANgDABIACQqEJsYAANgDAAAA.Grafbear:BAAANQAECgEIAQAAAA==.Grafknight:BAAANQADCgUIBwAAAA==.Graflock:BAAANQADCgUIBQAAAA==.Grafstab:BAAANQADCgQIBAAAAA==.',
Ha='Hawthorne:BAAANQAECgcIEwABNQAFFAIIAgAGAAAAAA==.',
Hi='Hiccups:BAAANQADCgUIBQAAAA==.',
Ja='Jandrina:BAAANQADCggIFgAAAA==.Janeta:BAAANQADCgYIBwAAAA==.Jaws:BAAANQADCgYIDAAAAA==.Jaywood:BAAANQAECgMIBQAAAA==.Jazarah:BAAANQADCgQIBQAAAA==.',
Je='Jeffronia:BAAANQADCgEIAQAAAA==.Jenny:BAAANQAECgQIBAABNQAECgUIBgAGAAAAAA==.Jeromy:BAAANQAECgIIAgAAAA==.',
Ju='Judgynomnom:BAABNQAECn8bAAITAAkKJyKDCwBsAwATAAkKJyKDCwBsAwAAAA==.',
Ka='Kavdh:BAAANQAECgYICQAAAA==.Kaygomei:BAAANQADCgYIBgAAAA==.',
Ks='Kshot:BAABNQAECn8sAAIJAAoK+BkoAwDpAgAJAAoK+BkoAwDpAgAAAA==.',
Ku='Kungpoo:BAAANQAECgMIAwAAAA==.',
['Kí']='Kílgrave:BAABNQAECn8aAAIUAAcKygMLFADoAAAUAAcKygMLFADoAAAAAA==.',
La='Lamuna:BAAANQAECgYICgAAAA==.Lanachan:BAABNQAECn8rAAIVAAoKnRCUMQBJAQAVAAoKnRCUMQBJAQAAAA==.',
Ld='Ldn:BAABNQAECn8iAAICAAgK3hPGDQDTAQACAAgK3hPGDQDTAQAAAA==.',
Li='Liz:BAABNQAECn8WAAIHAAYKAgPs9wATAQAHAAYKAgPs9wATAQAAAA==.',
Lo='Loy:BAAANQAECgEIAQAAAA==.',
Lu='Lunchable:BAAANQAECgIIAwAAAA==.',
Ly='Lylieth:BAABNQAECn8pAAIRAAkKQBB0KABPAQARAAkKQBB0KABPAQAAAA==.',
Ma='Macdrizzo:BAAANQAECgQICgAAAA==.Macie:BAAANQADCgEIAQAAAA==.Madflavor:BAAANQAECgYIDwAAAA==.Maestro:BAAANQADCgEIAQAAAA==.',
Mc='Mckew:BAAANQABCgQIBAAAAA==.',
Mi='Missandei:BAAANQABCgQIBQABNQABCgcICAAGAAAAAA==.',
Mo='Mock:BAAANQADCgEIAQABNQAECggIGwANAOQNAA==.Mouthyhusky:BAABNQAECn8aAAIHAAoK5gygcQAuAgAHAAoK5gygcQAuAgAAAA==.',
Ni='Ninluv:BAAANQAECgMIAwAAAA==.',
No='Nonbeliever:BAAANQADCgUIBgAAAA==.',
Ny='Nyancat:BAAANQAECgQIBAAAAA==.',
Oo='Oojni:BAABNQAECn8YAAMEAAYK8hBEJQAIAQAEAAUK3glEJQAIAQAWAAYK8QeJuwD0AAAAAA==.',
Pa='Pantheon:BAAANQADCgMIAwAAAA==.Pazzman:BAAANQADCgUIBAAAAA==.',
Ph='Pharhar:BAABNQAECn8qAAMTAAoKjCIoBgBsAgATAAoKjCIoBgBsAgAXAAEKTg578QA7AAAAAA==.',
Po='Poppachàdson:BAABNQAECn8YAAIEAAgKeB13EABiAgAEAAgKeB13EABiAgAAAA==.Poppadadson:BAAANQAECgcICQABNQAECggIGAAEAHgdAA==.',
Pr='Primex:BAAANQAECgYIBQAAAA==.',
Pu='Pukebucket:BAAANQAFFAMIAwAAAA==.Punished:BAAANQADCgEIAQAAAA==.Puscifer:BAAANQADCggIEAAAAA==.',
Qu='Qualil:BAAANQADCgUICAABNQAECgYIIgAKACURAA==.Quxxi:BAAANQADCgIIAgAAAA==.',
Ra='Ragewyrm:BAAANQADCgUIBQAAAA==.Raizel:BAAANQAECgIIAgABNQAECgoKOgAMAAkeAA==.Ravister:BAAANQAECgEIAQABNQAFFAUIDQAKANgZAA==.',
Re='Reinhart:BAABNQAECn8eAAIFAAgKwg3eXQB6AQAFAAgKwg3eXQB6AQAAAA==.Relic:BAACNQAFFH8NAAIYAAUK/QijCQBQAQAYAAUK/QijCQBQAQA1AAQKfycAAxgACgpnHAwgAIsCABgACgpnHAwgAIsCAAUAAQrEFqnFAD0AAAAA.Reneia:BAABNQAECn82AAIFAAoKvx/zAQCoAgAFAAoKvx/zAQCoAgABNQABCgIIAgAGAAAAAA==.Renk:BAABNQAECn8kAAIZAAcKUyaqBAD1AQAZAAcKUyaqBAD1AQAAAA==.',
Rh='Rhllor:BAAANQAECggIBwABNQABCgcICAAGAAAAAA==.Rhíza:BAABNQAECn8YAAINAAYK4At8ZgAzAQANAAYK4At8ZgAzAQAAAA==.',
Sa='Saeyl:BAAANQADCggIDAABNQAECgYIIgAKACURAA==.Samesarian:BAAANQADCgEIAQAAAA==.Sammie:BAEBNQAECn8ZAAIaAAkK4RYJBwBPAgAaAAkK4RYJBwBPAgABNQAECggIEAAGAAAAAA==.Sayl:BAABNQAECn8iAAQKAAYKJRHkNwBmAQAKAAYKJRHkNwBmAQAOAAUKJQNF1ACqAAAUAAQKsgZKGQCkAAAAAA==.',
Sc='Scallywinkle:BAAANQADCgQIBAAAAA==.',
Sh='Shaki:BAAANQADCgMIAwABNQAECgMIAwAGAAAAAA==.Shamewow:BAACNQAFFH8VAAIWAAYKdxZVBwDlAQAWAAYKdxZVBwDlAQA1AAQKfzQAAhYACgrCG3Y1AIoCABYACgrCG3Y1AIoCAAAA.Sheam:BAAANQAECgMIAwAAAA==.',
Si='Sicknnasty:BAACNQAFFH8VAAIFAAYKVxprCwCeAQAFAAYKVxprCwCeAQA1AAQKf0sAAwUACgoyIsQGAIsDAAUACgoyIsQGAIsDABkABwqiFqpQANEBAAAA.',
So='Sos:BAAANQADCgQIBAAAAA==.',
Sp='Speed:BAAANQAECgIIAgAAAA==.Spicytuna:BAAANQADCgYICwAAAA==.',
St='Starshopping:BAAANQADCgUICgABNQAECgoKHgALAIwWAA==.',
Su='Sunari:BAAANQADCgUICgAAAA==.',
Ta='Taelium:BAACNQAFFH8JAAIbAAYKGBPUBQBCAQAbAAYKGBPUBQBCAQA1AAQKfyQAAxsACgowICkMANcCABsACgowICkMANcCABcABwqRDEDVAHEBAAAA.Talrip:BAABNQAECn8fAAIcAAkKSxdNCABzAgAcAAkKSxdNCABzAgAAAA==.Tandsondsong:BAAANQAECgEIAgAAAA==.Tanfer:BAAANQAECgMIAwABNQAECgYICgAGAAAAAA==.',
Th='Thalaneth:BAAANQAECgYIBgAAAA==.Thalindra:BAAANQADCggIDwAAAA==.',
To='Toatem:BAAANQADCgUIBwAAAA==.Torope:BAACNQAFFH8QAAIBAAYKYA2RDgDpAAABAAYKYA2RDgDpAAA1AAQKfzMAAgEACgpZIUc5ABUDAAEACgpZIUc5ABUDAAAA.',
Tr='Trappynomnom:BAAANQAECgIIAgAAAA==.Tree:BAAANQAFFAEIAQABNQAFFAIIBgATADshAA==.',
Tz='Tzungxie:BAABNQAECn8rAAMdAAoKDx4UDgBnAQAeAAYKdRe3QQDEAQAdAAoK9R0UDgBnAQAAAA==.',
Uh='Uhohsocold:BAAANQADCgEIAQAAAA==.',
Un='Unholylord:BAACNQAFFH8NAAIKAAUK2BmyBQDXAQAKAAUK2BmyBQDXAQA1AAQKfzgABA4ACgr8IXIBAIoDAA4ACQrMIXIBAIoDAAoACgoTJfAEAIkDABQAAQr+GhQlAEQAAAAA.',
Va='Valinia:BAAANQADCgQIBAABNQAECgYICgAGAAAAAA==.',
Vi='Vitali:BAAANQAECgcIDAABNQAFFAUIDQAKANgZAA==.',
Wh='Whack:BAAANQADCgEIAQAAAA==.Whoa:BAAANQADCgYICwAAAA==.',
Wi='Wiigo:BAAANQADCggIFwABNQAECgoKPAAIAPMdAA==.',
Ye='Yearofspear:BAEANQAECgEIAQABNQAECggIEAAGAAAAAA==.',
Yi='Yirnkal:BAAANQABCgMIAwAAAA==.',
Yo='Yogybear:BAAANQADCgEIAQAAAA==.',
Ys='Ystarian:BAABNQAECn89AAMfAAoKDxrKCgC/AgAfAAoKDxrKCgC/AgAgAAYK0xLfEAApAQAAAA==.',
Yu='Yummerz:BAAANQADCgIIAgAAAA==.',
Za='Zami:BAAANQADCgYIBgAAAA==.Zaya:BAAANQADCgYIBgAAAA==.',
Zo='Zombiheals:BAAANQAECgIIAgABNQAECgMIBAAGAAAAAA==.',
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
