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

local lookup = {'Mage-Arcane','Mage-Frost','Monk-Brewmaster','Monk-Windwalker','Unknown-Unknown','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Priest-Shadow','Druid-Restoration','Druid-Balance','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warrior-Protection','Paladin-Holy','Priest-Discipline','Warrior-Arms','Paladin-Retribution','Paladin-Protection','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Outlaw','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=53,date='2026-10-27',data={Ag='Aggressíon:BAABNQAECn8mAAMBAAkKNxwUZgB9AQABAAgK1xsUZgB9AQACAAIKCyCLJwC3AAAAAA==.',
Ai='Airen:BAAANQAECgMIAgAAAA==.',
Al='Allywafflez:BAAANQAECgIIAgAAAA==.Alphadots:BAAANQAECgQIBAAAAA==.',
An='Anarsonista:BAAANQAECgQIDAAAAA==.',
Ap='Apachaler:BAABNQAECn82AAMDAAoKWBz+BQD0AgADAAoKWBz+BQD0AgAEAAYKzRJ6IwAJAQAAAA==.Appoc:BAAANQAECgQIEgAAAA==.',
Ar='Arathael:BAAANQABCgIIAgAAAA==.Araun:BAAANQADCgYIDAAAAA==.',
As='Asian:BAAANQAECgcIDQAAAA==.',
At='Atzula:BAAANQAECgUIBgABNQAECgcIBgAFAAAAAA==.',
Az='Azriel:BAAANQADCgIIAwAAAA==.',
Ba='Babyshamz:BAABNQAECn8VAAIGAAYKOAnZcgDlAAAGAAYKOAnZcgDlAAAAAA==.Babyzen:BAAANQADCggIIgAAAA==.Barca:BAAANQABCgEJAQAAAA==.Barranphalnx:BAABNQAECn8gAAIHAAoK9hy7BgBkAgAHAAoK9hy7BgBkAgAAAA==.',
Bb='Bbldrizzy:BAAANQADCgMIAwAAAA==.',
Be='Bearorrist:BAAANQAECggIDwABNQAFFAcIFgAIABwbAA==.Beefydomo:BAAANQADCgYIDwABNQAECgcICwAFAAAAAA==.Bekspriest:BAAANQAECgIIAgAAAA==.Betsy:BAAANQAECgQIBwAAAA==.',
Bi='Bigboybek:BAAANQAECgIIBAAAAA==.',
Bl='Blackgarden:BAAANQAECgYICgAAAA==.',
Bo='Bojanglez:BAAANQABCgIIAgAAAA==.',
Bu='Built:BAABNQAECn8bAAQJAAkKXxxQSQCRAgAJAAgK7h5QSQCRAgAKAAMKdA/YXgCrAAALAAIKCQ0/EAB4AAAAAA==.Bulshight:BAAANQAECgQIBAAAAA==.Buschlight:BAAANQADCgEIAQAAAA==.',
Ca='Cabbage:BAAANQAECgIIAQAAAA==.Carbonara:BAAANQAECgQIBAAAAA==.Castrator:BAAANQABCgUIBwAAAA==.Caudle:BAAANQAECgQIBAAAAA==.',
Ce='Celedor:BAAANQADCgYIBgABNQAFFAUIDQAMANgZAA==.',
Ch='Chaos:BAABNQAECn86AAMLAAoKjiSQAAApAwALAAoKjiSQAAApAwAJAAQKnCQe3wBDAQAAAA==.Chaosfu:BAABNQAECn8hAAIEAAoKcRpEIAAsAgAEAAoKcRpEIAAsAgABNQAECgoKOgALAI4kAA==.Chaossassin:BAAANQAECgcIBwABNQAECgoKOgALAI4kAA==.Chimatsuri:BAACNQAFFH8TAAIEAAgKpBJ6BAD+AQAEAAgKpBJ6BAD+AQA1AAQKfzYAAgQACgo6IAYQAOYCAAQACgo6IAYQAOYCAAAA.Choal:BAAANQADCgIIAgAAAA==.',
Cl='Clawreece:BAAANQABCggIGgAAAA==.Clyde:BAAANQADCggICAAAAA==.',
Co='Conta:BAAANQADCgYIBgAAAA==.',
Cu='Cuchicu:BAABNQAECn9DAAMNAAoKMCBXAwB0AwANAAoKMCBXAwB0AwAOAAIKXhCTbwAxAAAAAA==.',
Da='Damagexx:BAAANQADCgYIBgAAAA==.',
De='Deladre:BAEANQAECggIEAAAAA==.Desim:BAAANQABCgQIBAAAAA==.Dez:BAAANQAECgUIDwAAAA==.',
Di='Diaperbaby:BAABNQAECn8cAAIPAAkK9RXsQwBcAgAPAAkK9RXsQwBcAgAAAA==.',
Dk='Dkamp:BAAANQADCgcIIAAAAA==.',
Do='Dokken:BAAANQAECgIIAgAAAA==.',
Dr='Dragondie:BAAANQADCgYIBgABNQAECgIIAgAFAAAAAA==.Drdot:BAAANQAECgMIAwAAAA==.Drewcifer:BAACNQAFFH8UAAMQAAcK7xtXBQAEAgAQAAcK7xtXBQAEAgARAAEKtQtsFgBAAAA1AAQKfy0AAxAACgrPIyUEACQDABAACgpvIyUEACQDABEACAp/HDkgAEwCAAAA.Drewwar:BAAANQADCggICAABNQAFFAcIFAAQAO8bAA==.',
['Dü']='Düsk:BAAANQADCgcIDAAAAA==.',
Eh='Ehato:BAAANQADCgQIBAABNQAECgIIAgAFAAAAAA==.',
El='Ellie:BAAANQAECgEIAQAAAA==.',
Eu='Eurekuh:BAAANQADCgYIBwAAAA==.',
Fh='Fhephok:BAAANQADCgEIAQAAAA==.',
Fl='Floral:BAABNQAECn8cAAIOAAgK5A1oVQCDAQAOAAgK5A1oVQCDAQAAAA==.',
Fo='Fomo:BAAANQADCgIIAgAAAA==.',
Fr='Francis:BAAANQADCgEIAQAAAA==.',
Ga='Galbsadi:BAABNQAECn8qAAISAAkKyw0/XABPAQASAAkKyw0/XABPAQAAAA==.Galkadin:BAAANQAECgQIBAABNQAECgkJJgABADccAA==.Garra:BAAANQABCgUIBQAAAA==.',
Gl='Gladdie:BAACNQAFFH8eAAIIAAcKKRmMBwDrAQAIAAcKKRmMBwDrAQA1AAQKf0EAAggACgpBH28HAN0CAAgACgpBH28HAN0CAAAA.',
Go='Gormon:BAAANQAECgEIAQAAAA==.',
Gr='Graf:BAACNQAFFH8aAAITAAYKLiKIAABRAgATAAYKLiKIAABRAgA1AAQKfzMAAhMACQryJsYAANgDABMACQryJsYAANgDAAAA.Grafbear:BAAANQAECgYIBwAAAA==.Grafknight:BAAANQADCgUIBwAAAA==.Graflock:BAAANQADCgUIBQAAAA==.Grafstab:BAAANQADCgQIBAAAAA==.',
Ha='Hawthorne:BAAANQAECgcIEwABNQAFFAIIAgAFAAAAAA==.',
He='Heals:BAAANQADCgQIBAAAAA==.',
Hi='Hiccups:BAAANQADCgUIBQAAAA==.',
Ja='Jandrina:BAAANQADCggIFgAAAA==.Janeta:BAAANQADCgYIBwAAAA==.Jaws:BAAANQADCgYIDAAAAA==.Jaywood:BAAANQAECgMIBAAAAA==.Jazarah:BAAANQADCgQIBQAAAA==.',
Je='Jeffronia:BAAANQADCgEIAQAAAA==.Jenny:BAAANQAECgQIBAABNQAECgcIBgAFAAAAAA==.Jeromy:BAAANQAECgIIAgAAAA==.',
Ju='Judgynomnom:BAABNQAECn8bAAIUAAkKJyKDCwBsAwAUAAkKJyKDCwBsAwAAAA==.',
Ka='Kavdh:BAAANQAECgYICQAAAA==.Kaygomei:BAAANQAECgIIAgAAAA==.',
Ks='Kshot:BAABNQAECn8xAAILAAoKihooAwDpAgALAAoKihooAwDpAgAAAA==.',
Ku='Kungpoo:BAAANQAECgUIAwAAAA==.',
['Kí']='Kílgrave:BAABNQAECn8gAAIVAAcKxQQLFADoAAAVAAcKxQQLFADoAAAAAA==.',
La='Lamuna:BAAANQAECgYICgAAAA==.Lanachan:BAABNQAECn8zAAIWAAoKnRDQjQD6AQAWAAoKnRDQjQD6AQAAAA==.',
Ld='Ldn:BAABNQAECn8pAAICAAgKJxXGDQDTAQACAAgKJxXGDQDTAQAAAA==.',
Li='Liz:BAABNQAECn8WAAIJAAYKAgPs9wATAQAJAAYKAgPs9wATAQAAAA==.',
Lo='Loy:BAAANQAECgQIBQAAAA==.',
Lu='Lunchable:BAAANQAECgIIAwAAAA==.',
Ly='Lylieth:BAABNQAECn8uAAISAAoKUg+NPwCrAQASAAoKUg+NPwCrAQAAAA==.',
Ma='Macdrizzo:BAAANQAECgUIDAABNQAECgYIBQAFAAAAAA==.Macie:BAAANQADCgEIAQAAAA==.Madflavor:BAAANQAECgYIDwAAAA==.Maestro:BAAANQADCgEIAQAAAA==.Magicmeercat:BAAANQABCgEIAQAAAA==.Maranweh:BAAANQAECgYIBgABNQAECgcIBgAFAAAAAA==.',
Mc='Mckew:BAAANQABCgQIBAAAAA==.',
Mi='Missandei:BAAANQAECgcIBgABNQAECgQIBAAFAAAAAA==.',
Mo='Mock:BAAANQADCgEIAQABNQAECggIHAAOAOQNAA==.Mouthyhusky:BAABNQAECn8eAAIJAAoKOQ2gcQAuAgAJAAoKOQ2gcQAuAgAAAA==.',
Ni='Ninluv:BAAANQAECgMIAwAAAA==.',
No='Nonbeliever:BAAANQADCgUIBgAAAA==.',
Ny='Nyancat:BAAANQAECgcICwAAAA==.',
Oo='Oojni:BAABNQAECn8YAAMHAAYK8hBEJQAIAQAHAAUK3glEJQAIAQAGAAYK8QeJuwD0AAAAAA==.',
Pa='Pantheon:BAAANQADCgMIAwAAAA==.Pazzman:BAAANQADCgQIBAAAAA==.',
Ph='Pharhar:BAABNQAECn8vAAMUAAoK6iKMEQBCAwAUAAoK6iKMEQBCAwAXAAEKTg5FmQE7AAAAAA==.',
Po='Poppachàdson:BAABNQAECn8YAAIHAAgKeB13EABiAgAHAAgKeB13EABiAgAAAA==.Poppadadson:BAAANQAECgcICQABNQAECggIGAAHAHgdAA==.',
Pr='Primex:BAAANQAECgUIDQAAAA==.',
Pu='Pukebucket:BAABNQAFFH8FAAIYAAUKKBDOAgAMAQAYAAUKKBDOAgAMAQAAAA==.Punished:BAAANQADCgEIAQAAAA==.Puscifer:BAAANQADCggIEAAAAA==.',
Qu='Qualil:BAAANQAECgYIBgABNQAECgYIIgAMACURAA==.Quxxi:BAAANQADCgIIAgAAAA==.',
Ra='Ragewyrm:BAAANQADCgUIBQAAAA==.Raizel:BAAANQAECgIIAgABNQAECgoKQwANADAgAA==.Ravister:BAAANQAECgEIAQABNQAFFAUIDQAMANgZAA==.',
Re='Reinhart:BAABNQAECn8fAAIIAAgKwg3eXQB6AQAIAAgKwg3eXQB6AQAAAA==.Relic:BAACNQAFFH8OAAIZAAYKsQjOBgADAQAZAAYKsQjOBgADAQA1AAQKfzAAAxkACgq/HUISAE8CABkACgq/HUISAE8CAAgAAQrEFqnFAD0AAAAA.Reneia:BAABNQAECn85AAIIAAoKvx+PDgBdAgAIAAoKvx+PDgBdAgABNQABCgIIAgAFAAAAAA==.Renk:BAABNQAECn8qAAIaAAcKUyZBGAD8AgAaAAcKUyZBGAD8AgAAAA==.',
Rh='Rhllor:BAAANQAECgcIBwABNQAECgQIBAAFAAAAAA==.Rhíza:BAABNQAECn8YAAIOAAYK4At8ZgAzAQAOAAYK4At8ZgAzAQAAAA==.',
Ro='Roughneck:BAAANQADCggICgAAAA==.',
Sa='Saeyl:BAAANQADCggIDAABNQAECgYIIgAMACURAA==.Samesarian:BAAANQADCgEIAQAAAA==.Sammie:BAEBNQAECn8aAAIbAAoKNhYJBwBPAgAbAAoKNhYJBwBPAgABNQAECggIEAAFAAAAAA==.Sayl:BAABNQAECn8iAAQMAAYKJRHkNwBmAQAMAAYKJRHkNwBmAQAPAAUKJQNF1ACqAAAVAAQKsgZKGQCkAAAAAA==.',
Sc='Scallywinkle:BAAANQADCgQIBAAAAA==.',
Sh='Shaki:BAAANQADCgMIAwABNQAECgMIAwAFAAAAAA==.Shamewow:BAACNQAFFH8WAAIGAAcKMxdVBwDlAQAGAAcKMxdVBwDlAQA1AAQKfz0AAgYACgpOHTMWAJUCAAYACgpOHTMWAJUCAAAA.Sheam:BAAANQAECgMIAwAAAA==.',
Si='Sicknnasty:BAACNQAFFH8WAAIIAAcKHBtrCwCeAQAIAAcKHBtrCwCeAQA1AAQKf1YAAwgACgo4I8QGAIsDAAgACgo4I8QGAIsDABoACAqlFqpQANEBAAAA.',
So='Sos:BAAANQADCgQIBAAAAA==.',
Sp='Speed:BAAANQAECgIIAgAAAA==.Spicytuna:BAAANQADCgYIDgAAAA==.',
St='Starshopping:BAAANQADCgUICgABNQAECgoKOgALAI4kAA==.',
Su='Sunari:BAAANQADCgUICgAAAA==.',
Ta='Taelium:BAACNQAFFH8KAAIYAAYK7hTUBQBCAQAYAAYK7hTUBQBCAQA1AAQKfywAAxgACgowIPYEAL8CABgACgowIPYEAL8CABcABwqRDEDVAHEBAAAA.Talrip:BAABNQAECn8gAAIcAAoK5hdNCABzAgAcAAoK5hdNCABzAgAAAA==.Tandsondsong:BAAANQAECgEIAgAAAA==.Tanfer:BAAANQAECgMIAwABNQAECgYICgAFAAAAAA==.',
Th='Thalaneth:BAAANQAECgYIBgAAAA==.Thalindra:BAAANQADCggIDwAAAA==.',
To='Toatem:BAAANQADCgUIBwAAAA==.Torope:BAACNQAFFH8RAAIBAAcK/gpcDQArAQABAAcK/gpcDQArAQA1AAQKfzwAAgEACgpjIlALAP0CAAEACgpjIlALAP0CAAAA.',
Tr='Trappynomnom:BAAANQAECgIIAgAAAA==.Tree:BAAANQAFFAEIAQABNQAFFAIIBgAUADshAA==.',
Tz='Tzungxie:BAABNQAECn80AAMdAAoKxB69EwCFAgAdAAoKqh69EwCFAgAeAAYKdRe3QQDEAQAAAA==.',
Uh='Uhohsocold:BAAANQADCgEIAQAAAA==.',
Un='Unholylord:BAACNQAFFH8NAAIMAAUK2BmyBQDXAQAMAAUK2BmyBQDXAQA1AAQKf0IABAwACgoQJtwAAHADAAwACgoQJtwAAHADAA8ACQrMIXAHAGkDABUAAQr+GhQlAEQAAAAA.',
Va='Valinia:BAAANQADCgQIBAABNQAECgYICgAFAAAAAA==.',
Vi='Vitali:BAAANQAFFAEIAQABNQAFFAUIDQAMANgZAA==.',
Wh='Whack:BAAANQADCgEIAQAAAA==.Whoa:BAAANQADCgYICwAAAA==.',
Wi='Wiigo:BAAANQAECgUIBQABNQAECgcIDAAFAAAAAA==.',
Ye='Yearofspear:BAEANQAECgEIAQABNQAECggIEAAFAAAAAA==.',
Yi='Yirnkal:BAAANQABCgMIAwAAAA==.',
Yo='Yogybear:BAAANQADCgEIAQAAAA==.',
Ys='Ystarian:BAACNQAFFH8FAAIfAAIKnghXBAB6AAAfAAIKnghXBAB6AAA1AAQKf0QAAx8ACgoFG8oKAL8CAB8ACgoFG8oKAL8CACAABgrTEt8QACkBAAAA.',
Yu='Yummerz:BAAANQADCgIIAgAAAA==.',
Za='Zami:BAAANQADCgYIBgAAAA==.Zaya:BAAANQADCgYIBgAAAA==.',
Zo='Zombiheals:BAAANQAECgIIAgABNQAECgMIBAAFAAAAAA==.',
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
