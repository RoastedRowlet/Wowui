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

local lookup = {'Mage-Arcane','Mage-Frost','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Priest-Shadow','Druid-Restoration','Druid-Balance','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Demonology','Warrior-Protection','Monk-Mistweaver','Paladin-Holy','Priest-Discipline','Warrior-Arms','Paladin-Retribution','Paladin-Protection','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Outlaw','DemonHunter-Vengeance','Mage-Fire','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=53,date='2026-11-10',data={Ag='Aggressíon:BAABNQAECn83AAMBAAoKWB60YwDeAQABAAkKVB60YwDeAQACAAIKCyCLJwC3AAAAAA==.',
Ai='Airen:BAAANQAECgIIAgAAAA==.',
Al='Allywafflez:BAAANQAECgIIAgAAAA==.Alphadots:BAAANQAECgUICgAAAA==.',
An='Anarsonista:BAAANQAECgQIDAAAAA==.Annalisea:BAAANQADCggICAABNQABCgIIAgADAAAAAA==.',
Ap='Apachaler:BAABNQAECn9AAAMEAAoKOR3+BQD0AgAEAAoKOR3+BQD0AgAFAAYKzRKMMAABAQAAAA==.Appoc:BAAANQAECgQIEgAAAA==.',
Ar='Arathael:BAAANQABCgIIAgAAAA==.Araun:BAAANQADCgYIDAAAAA==.',
As='Asian:BAAANQAECgcIDQAAAA==.',
At='Atzula:BAAANQAECgUIBgABNQAECgcIBgADAAAAAA==.',
Az='Azriel:BAAANQADCgIIAwAAAA==.',
Ba='Babyshamz:BAABNQAECn8dAAIGAAcKkgjQjAD6AAAGAAcKkgjQjAD6AAAAAA==.Babyzen:BAAANQADCggIKQAAAA==.Barca:BAAANQABCgEJAQAAAA==.Barranphalnx:BAABNQAECn8mAAIHAAoKVR5+CACOAgAHAAoKVR5+CACOAgAAAA==.',
Bb='Bbldrizzy:BAAANQADCgMIAwAAAA==.',
Be='Bearorrist:BAAANQAECggIDwABNQAFFAcIFgAIABwbAA==.Beefydomo:BAAANQADCgYIDwABNQAECgcIDwADAAAAAA==.Bekspriest:BAAANQAECgYIDAAAAA==.Betsy:BAAANQAECgQIBwAAAA==.',
Bi='Bigboybek:BAAANQAECggIDgAAAA==.',
Bl='Blackgarden:BAAANQAECgYICgAAAA==.',
Bo='Bobspriest:BAAANQAECgYIBgAAAA==.Bojanglez:BAAANQABCgIIAgAAAA==.',
Bu='Built:BAABNQAECn8bAAQJAAkKXxxQSQCRAgAJAAgK7h5QSQCRAgAKAAMKdA/YXgCrAAALAAIKCQ0/EAB4AAAAAA==.Bulshight:BAAANQAECgUIBQAAAA==.Buschlight:BAAANQADCgEIAQAAAA==.',
Ca='Cabbage:BAAANQAECgIIAQAAAA==.Carbonara:BAAANQAECgQIBAAAAA==.Castrator:BAAANQABCgUIBwAAAA==.Caudle:BAAANQAECgQIBAAAAA==.',
Ce='Celedor:BAAANQADCgYIBgABNQAFFAUIDQAMANgZAA==.',
Ch='Chaos:BAABNQAECn9NAAMLAAoKKiWCAABcAwALAAoKKiWCAABcAwAJAAQKnCQe3wBDAQAAAA==.Chaosfu:BAABNQAECn8kAAIFAAoKcRpEIAAsAgAFAAoKcRpEIAAsAgABNQAECgoKTQALAColAA==.Chaossassin:BAAANQAECggIEQABNQAECgoKTQALAColAA==.Chimatsuri:BAACNQAFFH8TAAIFAAgKpBJ6BAD+AQAFAAgKpBJ6BAD+AQA1AAQKfzcAAgUACgo6IAYQAOYCAAUACgo6IAYQAOYCAAAA.Choal:BAAANQADCgIIAgAAAA==.',
Cl='Clawreece:BAAANQABCggIGgAAAA==.Clyde:BAAANQADCggICAAAAA==.',
Co='Conta:BAAANQAECgIIAgAAAA==.',
Cu='Cuchicu:BAABNQAECn9QAAMNAAoKziLgAgDSAwANAAoKziLgAgDSAwAOAAIKXhBbhwAvAAAAAA==.',
Da='Damagexx:BAAANQADCgYIBgAAAA==.Dargra:BAAANQAECggICAAAAA==.',
De='Deladre:BAEANQAECggIEAAAAA==.Desim:BAAANQABCgQIBAAAAA==.Dez:BAAANQAECgUIDwAAAA==.',
Di='Diaperbaby:BAABNQAECn8cAAIPAAkK9RXsQwBcAgAPAAkK9RXsQwBcAgAAAA==.',
Dk='Dkamp:BAAANQADCggILwAAAA==.',
Do='Dokken:BAAANQAECgIIAgAAAA==.',
Dr='Dragondie:BAAANQADCgYIBgABNQAECggICAADAAAAAA==.Drdot:BAAANQAECgMIAwAAAA==.Drewcifer:BAACNQAFFH8UAAMQAAcK7xtXBQAEAgAQAAcK7xtXBQAEAgARAAEKtQtsFgBAAAA1AAQKfy0AAxAACgrPI78IAAADABAACgpvI78IAAADABEACAp/HDkgAEwCAAAA.Drewwar:BAAANQADCggICAABNQAFFAcIFAAQAO8bAA==.',
['Dü']='Düsk:BAAANQADCgcIDAAAAA==.',
Eh='Ehato:BAAANQADCgQIBAABNQAECggICAADAAAAAA==.',
El='Ellie:BAAANQAECgIIAQAAAA==.',
Et='Etticey:BAAANQADCgUIBQABNQAECgkJJAASAFUSAA==.',
Eu='Eurekuh:BAAANQADCgYIBwAAAA==.',
Fh='Fhephok:BAAANQADCgEIAQAAAA==.',
Fl='Floral:BAABNQAECn8sAAIOAAkK4Q4ULwB2AQAOAAkK4Q4ULwB2AQAAAA==.',
Fo='Fomo:BAAANQAECgEIAQAAAA==.',
Fr='Francis:BAAANQADCgEIAQAAAA==.',
Ga='Galbsadi:BAABNQAECn8yAAITAAoKqQ0GXgCnAQATAAoKqQ0GXgCnAQAAAA==.Galkadin:BAAANQAECgUIDgABNQAECgoKNwABAFgeAA==.Garra:BAAANQABCgUIBQAAAA==.',
Gl='Gladdie:BAACNQAFFH8eAAIIAAcKKRmMBwDrAQAIAAcKKRmMBwDrAQA1AAQKf0UAAggACgpbIjkIAAADAAgACgpbIjkIAAADAAAA.',
Go='Gormon:BAAANQAECgEIAQAAAA==.',
Gr='Graf:BAACNQAFFH8aAAIUAAYKLiKIAABRAgAUAAYKLiKIAABRAgA1AAQKfz4AAhQACgrxJhQAAJ8DABQACgrxJhQAAJ8DAAAA.Grafbear:BAAANQAECgcIDgAAAA==.Grafknight:BAAANQADCgUIBwAAAA==.Graflock:BAAANQADCgUIBQAAAA==.Grafstab:BAAANQADCgQIBAAAAA==.',
Ha='Hawthorne:BAABNQAECn8gAAIVAAoKrRZyDgAfAgAVAAoKrRZyDgAfAgABNQAFFAIIAgADAAAAAA==.',
He='Heals:BAAANQADCgQIBAAAAA==.',
Hi='Hiccups:BAAANQADCgUIBQAAAA==.',
Ja='Jandrina:BAAANQAECgQIBQAAAA==.Janeta:BAAANQAECgQIBAAAAA==.Jaws:BAAANQADCgYIDAAAAA==.Jaywood:BAAANQAECgUIDQAAAA==.Jazarah:BAAANQADCgQIBQAAAA==.',
Je='Jeffronia:BAAANQADCgEIAQAAAA==.Jenny:BAAANQAECgQIBAABNQAECgcIBgADAAAAAA==.Jeromy:BAAANQAECgUIDQAAAA==.Jeronin:BAAANQAECgEIAQAAAA==.',
Ju='Judgynomnom:BAABNQAECn8bAAIWAAkKJyKDCwBsAwAWAAkKJyKDCwBsAwAAAA==.',
Ka='Kavdh:BAAANQAECgYICQAAAA==.Kaygomei:BAAANQAECgIIAgABNQAECggICAADAAAAAA==.',
Ks='Kshot:BAABNQAECn86AAILAAoKih2tAQDaAgALAAoKih2tAQDaAgAAAA==.',
Ku='Kungpoo:BAAANQAECgUIAwAAAA==.',
['Kí']='Kílgrave:BAABNQAECn8pAAIXAAkKXwW9CAAWAQAXAAkKXwW9CAAWAQAAAA==.',
La='Lamuna:BAAANQAECgYICgAAAA==.Lanachan:BAABNQAECn8/AAIYAAoKCBIOZwC1AQAYAAoKCBIOZwC1AQAAAA==.',
Ld='Ldn:BAABNQAECn81AAICAAoKIBNiCwDMAQACAAoKIBNiCwDMAQAAAA==.',
Li='Liz:BAABNQAECn8WAAIJAAYKAgPs9wATAQAJAAYKAgPs9wATAQAAAA==.',
Lo='Loy:BAAANQAECgUICwAAAA==.',
Lu='Lunchable:BAAANQAECgIIAwAAAA==.',
Ly='Lylieth:BAABNQAECn8uAAITAAoKUg+AYgCaAQATAAoKUg+AYgCaAQAAAA==.',
Ma='Macdrizzo:BAAANQAECgUIDAABNQAECgYICgADAAAAAA==.Macie:BAAANQADCgEIAQAAAA==.Madflavor:BAAANQAECgYIDwAAAA==.Maestro:BAAANQADCgEIAQAAAA==.Magicmeercat:BAAANQABCgEIAQAAAA==.Maranweh:BAAANQAECgYIBgABNQAECgcIBgADAAAAAA==.',
Mc='Mckew:BAAANQABCgQIBAAAAA==.',
Mi='Missandei:BAAANQAECggIEQABNQAECgQIBAADAAAAAA==.',
Mo='Mock:BAAANQADCgEIAQABNQAECgkJLAAOAOEOAA==.Monks:BAAANQAECgIIAgAAAA==.Mouthyhusky:BAACNQAFFH8FAAIJAAIKxwN5JAB7AAAJAAIKxwN5JAB7AAA1AAQKfyEAAgkACgpUDaBxAC4CAAkACgpUDaBxAC4CAAAA.',
My='Mythics:BAAANQADCggICAAAAA==.',
Ni='Ninluv:BAAANQAECgMIAwAAAA==.',
No='Nonbeliever:BAAANQADCgUIBgAAAA==.',
Ny='Nyancat:BAAANQAECgcIDwAAAA==.',
['Nï']='Nïfty:BAAANQADCgIIAgAAAA==.',
Oo='Oojni:BAABNQAECn8YAAMHAAYK8hBEJQAIAQAHAAUK3glEJQAIAQAGAAYK8QeJuwD0AAAAAA==.',
Pa='Pantheon:BAAANQADCgMIAwAAAA==.Pazzman:BAAANQAECgQIBAAAAA==.',
Ph='Pharhar:BAABNQAECn82AAMWAAoKOCOMEQBCAwAWAAoKOCOMEQBCAwAZAAEKTg5FmQE7AAAAAA==.',
Po='Poppachàdson:BAABNQAECn8YAAIHAAgKeB13EABiAgAHAAgKeB13EABiAgAAAA==.Poppadadson:BAAANQAECgcICQABNQAECggIGAAHAHgdAA==.',
Pr='Primex:BAAANQAECgYIDwAAAA==.',
Pu='Pukebucket:BAABNQAFFH8FAAIaAAUKKBCLBAD+AAAaAAUKKBCLBAD+AAAAAA==.Punished:BAAANQADCgEIAQAAAA==.Puscifer:BAAANQADCggIEAAAAA==.',
Qu='Qualil:BAAANQAECggICwAAAA==.Quxxi:BAAANQADCgIIAgAAAA==.',
Ra='Ragewyrm:BAAANQADCgUIBQAAAA==.Raizel:BAAANQAECgIIAgABNQAECgoKUAANAM4iAA==.Ravister:BAAANQAECgEIAQABNQAFFAUIDQAMANgZAA==.',
Re='Reinhart:BAABNQAECn8gAAIIAAkK2w3eXQB6AQAIAAkK2w3eXQB6AQAAAA==.Relic:BAACNQAFFH8PAAIbAAcKKAc/CAAzAQAbAAcKKAc/CAAzAQA1AAQKfzsAAxsACgq6HsQUAJoCABsACgq6HsQUAJoCAAgAAQrEFqnFAD0AAAAA.Reneia:BAABNQAECn9AAAIIAAoK+CFvFgD6AgAIAAoK+CFvFgD6AgABNQABCgIIAgADAAAAAA==.Renk:BAABNQAECn8zAAIcAAgKpSVBGAD8AgAcAAgKpSVBGAD8AgAAAA==.',
Rh='Rhllor:BAAANQAECggIDwABNQAECgQIBAADAAAAAA==.Rhíza:BAABNQAECn8YAAIOAAYK4At8ZgAzAQAOAAYK4At8ZgAzAQAAAA==.',
Ro='Roughneck:BAAANQAECgUIEAAAAA==.',
Sa='Saeyl:BAAANQADCggIDAABNQAECggICwADAAAAAA==.Samesarian:BAAANQADCgEIAQAAAA==.Sammie:BAEBNQAECn8aAAIdAAoKNhYJBwBPAgAdAAoKNhYJBwBPAgABNQAECggIEAADAAAAAA==.Sayl:BAABNQAECn8iAAQMAAYKJRHkNwBmAQAMAAYKJRHkNwBmAQAPAAUKJQNF1ACqAAAXAAQKsgZKGQCkAAABNQAECggICwADAAAAAA==.',
Sc='Scallywinkle:BAAANQADCgQIBAAAAA==.',
Sh='Shaki:BAAANQADCgMIAwABNQAECgMIAwADAAAAAA==.Shamewow:BAACNQAFFH8WAAIGAAcKMxdVBwDlAQAGAAcKMxdVBwDlAQA1AAQKf1AAAgYACgrKHfMYANsCAAYACgrKHfMYANsCAAAA.Sheam:BAAANQAECgMIAwAAAA==.',
Si='Sicknnasty:BAACNQAFFH8WAAIIAAcKHBtrCwCeAQAIAAcKHBtrCwCeAQA1AAQKf2AAAwgACgo4I8QGAIsDAAgACgo4I8QGAIsDABwACAqlFqpQANEBAAAA.',
Sm='Smoguls:BAAANQADCgYIBAAAAA==.',
So='Sos:BAAANQADCgQIBAAAAA==.',
Sp='Speed:BAAANQAECgIIAgAAAA==.Spicytuna:BAAANQADCgcIFQAAAA==.',
St='Starshopping:BAAANQADCgUICgABNQAECgoKTQALAColAA==.',
Su='Sunari:BAAANQADCgUICgAAAA==.',
Ta='Taelium:BAACNQAFFH8LAAIaAAYKNhfUBQBCAQAaAAYKNhfUBQBCAQA1AAQKfywAAxoACgowIBYJAJ4CABoACgowIBYJAJ4CABkABwqRDEDVAHEBAAE1AAUUBwgYAAgAThsA.Talrip:BAABNQAECn8hAAIeAAoKDBhNCABzAgAeAAoKDBhNCABzAgAAAA==.Tandsondsong:BAAANQAECgEIAgAAAA==.Tanfer:BAAANQAECgMIAwABNQAECgYICgADAAAAAA==.',
Th='Thalaneth:BAAANQAECgcIDwAAAA==.Thalindra:BAAANQADCggIDwAAAA==.',
To='Toatem:BAAANQADCgUIBwAAAA==.Torope:BAACNQAFFH8RAAIBAAcK/gryFwAbAQABAAcK/gryFwAbAQA1AAQKf0cAAwEACgoHJLMQAAUDAAEACgoHJLMQAAUDAB8AAgrzD2oLAD4AAAAA.',
Tr='Trappynomnom:BAAANQAECgIIAgAAAA==.Tree:BAAANQAFFAEIAQABNQAFFAIIBgAWADshAA==.',
Tz='Tzungxie:BAABNQAECn89AAMSAAoKxB7SFgC7AgASAAoKqh7SFgC7AgAgAAYKdRe3QQDEAQAAAA==.',
Uh='Uhohsocold:BAAANQADCgEIAQAAAA==.',
Un='Unholylord:BAACNQAFFH8NAAIMAAUK2BmyBQDXAQAMAAUK2BmyBQDXAQA1AAQKf0wABA8ACgovIDoKAIkDAA8ACgovIDoKAIkDAAwACgp1Jt0AAIMDABcAAQr+GhQlAEQAAAAA.',
Va='Valinia:BAAANQADCgQIBAABNQAECgYICgADAAAAAA==.',
Vi='Vitali:BAABNQAECn8YAAIaAAoKxyCyBQD3AgAaAAoKxyCyBQD3AgABNQAFFAUIDQAMANgZAA==.',
Wh='Whack:BAAANQADCgEIAQAAAA==.Whoa:BAAANQADCgYICwAAAA==.',
Wi='Wiigo:BAAANQAECgUICQABNQAECgoKUAAKAEAgAA==.',
Ye='Yearofspear:BAEANQAECgEIAQABNQAECggIEAADAAAAAA==.',
Yi='Yirnkal:BAAANQABCgMIAwAAAA==.',
Yo='Yogybear:BAAANQADCgEIAQAAAA==.',
Ys='Ystarian:BAACNQAFFH8IAAIhAAUKHwdLBACoAAAhAAUKHwdLBACoAAA1AAQKf1EAAyEACgp1HcoKAL8CACEACgp1HcoKAL8CACIABgrTEt8QACkBAAAA.',
Yu='Yummerz:BAAANQADCgIIAgAAAA==.',
Za='Zami:BAAANQADCgYIBgAAAA==.Zaya:BAAANQADCgYIBgAAAA==.',
Zo='Zombiheals:BAAANQAECgIIAgABNQAECgMIBAADAAAAAA==.',
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
