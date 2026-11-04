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
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=53,date='2026-11-03',data={Ag='Aggressíon:BAABNQAECn8vAAMBAAkKaBwWhABxAQABAAgKERwWhABxAQACAAIKCyCLJwC3AAAAAA==.',
Ai='Airen:BAAANQAECgMIAgAAAA==.',
Al='Allywafflez:BAAANQAECgIIAgAAAA==.Alphadots:BAAANQAECgQICQAAAA==.',
Am='Amethystos:BAAANQADCgEIAgAAAA==.',
An='Anarsonista:BAAANQAECgQIDAAAAA==.Annalisea:BAAANQADCggICAABNQABCgIIAgADAAAAAA==.',
Ap='Apachaler:BAABNQAECn9AAAMEAAoKOR1GBABSAgAEAAoKOR1GBABSAgAFAAYKzRIWLAACAQAAAA==.Appoc:BAAANQAECgQIEgAAAA==.',
Ar='Arathael:BAAANQADCgEIAQAAAA==.Araun:BAAANQADCgYIDQAAAA==.',
As='Asian:BAAANQAECgcIDQAAAA==.',
At='Atzula:BAAANQAECgUIBgABNQAECgcIBwADAAAAAA==.',
Az='Azriel:BAAANQADCgIIAwAAAA==.',
Ba='Babyshamz:BAABNQAECn8aAAIGAAYKVwmkigDkAAAGAAYKVwmkigDkAAAAAA==.Babyzen:BAAANQADCggIKQAAAA==.Barca:BAAANQADCgEIAQAAAA==.Barranphalnx:BAABNQAECn8jAAIHAAoKHB7pBwB+AgAHAAoKHB7pBwB+AgAAAA==.',
Bb='Bbldrizzy:BAAANQADCgMIAwAAAA==.',
Be='Bearorrist:BAAANQAECggIEgABNQAFFAcIFgAIABwbAA==.Beefydomo:BAAANQADCgYIDwABNQAECgcIEAADAAAAAA==.Bekspriest:BAAANQAECgQIBwAAAA==.Betsy:BAAANQAECgQIBwAAAA==.',
Bi='Bigboybek:BAAANQAECggIDQAAAA==.',
Bl='Blackgarden:BAAANQAECgYICgAAAA==.',
Bo='Bobspriest:BAAANQAECgYIBgAAAA==.Bogbooty:BAAANQAECgIIAwAAAA==.Bojanglez:BAAANQAECgEIAQAAAA==.',
Bu='Built:BAABNQAECn8bAAQJAAkKXxxQSQCRAgAJAAgK7h5QSQCRAgAKAAMKdA/YXgCrAAALAAIKCQ0/EAB4AAAAAA==.Bulshight:BAAANQAECgUIBgAAAA==.Buschlight:BAAANQADCgEIAQAAAA==.',
Ca='Cabbage:BAAANQAECgIIAQAAAA==.Campeador:BAAANQADCgEIAgAAAA==.Carbonara:BAAANQAECgQIBAAAAA==.Castrator:BAAANQABCgUIBwAAAA==.Caudle:BAAANQAECgQIBgAAAA==.',
Ce='Celedor:BAAANQADCgYIBgABNQAFFAUIDQAMANgZAA==.',
Ch='Chaos:BAABNQAECn9EAAMLAAoKByVyAABjAwALAAoKByVyAABjAwAJAAQKnCQe3wBDAQAAAA==.Chaosfu:BAABNQAECn8kAAIFAAoKcRpEIAAsAgAFAAoKcRpEIAAsAgABNQAECgoKRAALAAclAA==.Chaossassin:BAAANQAECggIEQABNQAECgoKRAALAAclAA==.Chimatsuri:BAACNQAFFH8TAAIFAAgKpBJ6BAD+AQAFAAgKpBJ6BAD+AQA1AAQKfzcAAgUACgo6IAYQAOYCAAUACgo6IAYQAOYCAAAA.Choal:BAAANQADCgIIAgAAAA==.',
Cl='Clawreece:BAAANQADCgEIAQAAAA==.Clyde:BAAANQADCggICAAAAA==.',
Co='Conta:BAAANQADCgYIBgAAAA==.',
Cu='Cuchicu:BAABNQAECn9MAAMNAAoKICLfAgC+AwANAAoKICLfAgC+AwAOAAIKXhAKfgAxAAAAAA==.',
Da='Damagexx:BAAANQADCgYIBwAAAA==.Dargra:BAAANQAECggICAAAAA==.Dazed:BAAANQADCgEIAQAAAA==.',
De='Deladre:BAEANQAECggIEQAAAA==.Desim:BAAANQADCgEIAQAAAA==.Dez:BAAANQAECgUIDwAAAA==.',
Di='Diaperbaby:BAABNQAECn8cAAIPAAkK9RXsQwBcAgAPAAkK9RXsQwBcAgAAAA==.',
Dk='Dkamp:BAAANQADCggIKAAAAA==.',
Do='Dokken:BAAANQAECgIIAgAAAA==.',
Dr='Dragondie:BAAANQADCgYIBgABNQAECggICAADAAAAAA==.Drdot:BAAANQAECgMIAwAAAA==.Drewcifer:BAACNQAFFH8UAAMQAAcK7xtXBQAEAgAQAAcK7xtXBQAEAgARAAEKtQtsFgBAAAA1AAQKfy0AAxAACgrPIy4HAAcDABAACgpvIy4HAAcDABEACAp/HDkgAEwCAAAA.Drewwar:BAAANQADCggICAABNQAFFAcIFAAQAO8bAA==.',
['Dü']='Düsk:BAAANQADCgcIDAAAAA==.',
Eh='Ehato:BAAANQADCgQIBAABNQAECggICAADAAAAAA==.',
El='Ellie:BAAANQAECgIIAQAAAA==.',
Et='Etticey:BAAANQADCgUIBQABNQAECgkJIQASAPgPAA==.',
Eu='Eurekuh:BAAANQADCgYIBwAAAA==.',
Fh='Fhephok:BAAANQADCgEIAQAAAA==.',
Fl='Floral:BAABNQAECn8kAAIOAAkKRA5oVQCDAQAOAAkKRA5oVQCDAQAAAA==.',
Fo='Fomo:BAAANQAECgEIAQAAAA==.',
Fr='Francis:BAAANQADCgEIAQAAAA==.',
Ga='Galbsadi:BAABNQAECn8wAAITAAkKyw2gaQBgAQATAAkKyw2gaQBgAQAAAA==.Galkadin:BAAANQAECgUICwABNQAECgkJLwABAGgcAA==.Garra:BAAANQADCgEIAQAAAA==.',
Gl='Gladdie:BAACNQAFFH8eAAIIAAcKKRmMBwDrAQAIAAcKKRmMBwDrAQA1AAQKf0QAAggACgodIooHAAADAAgACgodIooHAAADAAAA.',
Go='Gormon:BAAANQAECgEIAQAAAA==.',
Gr='Graf:BAACNQAFFH8aAAIUAAYKLiKIAABRAgAUAAYKLiKIAABRAgA1AAQKfz0AAhQACgrjJhMAAKADABQACgrjJhMAAKADAAAA.Grafbear:BAAANQAECgYIBwAAAA==.Grafknight:BAAANQADCgUIBwAAAA==.Graflock:BAAANQADCgUIBQAAAA==.Grafstab:BAAANQADCgQIBAAAAA==.',
Ha='Hawthorne:BAABNQAECn8gAAIVAAoKrRZjDAAnAgAVAAoKrRZjDAAnAgABNQAFFAIIAgADAAAAAA==.',
He='Heals:BAAANQADCgQIBAAAAA==.',
Hi='Hiccups:BAAANQADCgUIBQAAAA==.',
It='Ithrel:BAAANQADCgIIAgAAAA==.',
Ja='Jandrina:BAAANQAECgQIBQAAAA==.Janeta:BAAANQAECgQIBAAAAA==.Jaws:BAAANQADCgYIDAAAAA==.Jaywood:BAAANQAECgUIDgAAAA==.Jazarah:BAAANQADCgQIBQAAAA==.',
Je='Jeffronia:BAAANQADCgEIAQAAAA==.Jenny:BAAANQAECgQIBAABNQAECgcIBwADAAAAAA==.Jeromy:BAAANQAECgUIDgAAAA==.Jeronin:BAAANQAECgEIAQAAAA==.',
Jo='Jormunngandr:BAAANQADCgEIAQABNQAFFAgIEwAFAKQSAA==.',
Ju='Judgynomnom:BAABNQAECn8bAAIWAAkKJyKDCwBsAwAWAAkKJyKDCwBsAwAAAA==.',
Ka='Kavdh:BAAANQAECgYICQAAAA==.Kaygomei:BAAANQAECgIIAgABNQAECggICAADAAAAAA==.',
Ks='Kshot:BAABNQAECn85AAILAAoKhR17AQDfAgALAAoKhR17AQDfAgAAAA==.',
Ku='Kungpoo:BAAANQAECgUIBgAAAA==.',
['Kí']='Kílgrave:BAABNQAECn8lAAIXAAkKXwVVCAACAQAXAAkKXwVVCAACAQAAAA==.',
La='Lamuna:BAAANQAECgYICgAAAA==.Lanachan:BAABNQAECn85AAIYAAoKnRA2cgByAQAYAAoKnRA2cgByAQAAAA==.',
Ld='Ldn:BAABNQAECn8xAAICAAkK7RPGDQDTAQACAAkK7RPGDQDTAQAAAA==.',
Li='Liydan:BAAANQADCgEIAQAAAA==.Liz:BAABNQAECn8WAAIJAAYKAgPs9wATAQAJAAYKAgPs9wATAQAAAA==.',
Lo='Loy:BAAANQAECgQICQAAAA==.',
Lu='Lunchable:BAAANQAECgIIAwAAAA==.',
Ly='Lylieth:BAABNQAECn8uAAITAAoKUg9cVwCUAQATAAoKUg9cVwCUAQAAAA==.',
Ma='Macdrizzo:BAAANQAECgUIDAAAAA==.Macie:BAAANQADCgEIAQAAAA==.Madflavor:BAAANQAECgYIDwAAAA==.Maestro:BAAANQADCgEIAQAAAA==.Magicmeercat:BAAANQAECgEIAQAAAA==.Maranweh:BAAANQAECgYIBwABNQAECgcIBwADAAAAAA==.',
Mc='Mckew:BAAANQADCgEIAQAAAA==.',
Mi='Missandei:BAAANQAECggIEAABNQAECgQIBgADAAAAAA==.',
Mo='Mock:BAAANQADCgEIAQABNQAECgkJJAAOAEQOAA==.Monks:BAAANQADCgQIBAAAAA==.Mouthyhusky:BAACNQAFFH8FAAIJAAIKxwN4IAB+AAAJAAIKxwN4IAB+AAA1AAQKfyEAAgkACgpUDaBxAC4CAAkACgpUDaBxAC4CAAAA.',
Ni='Ninluv:BAAANQAECgMIAwAAAA==.',
No='Nonbeliever:BAAANQADCgUIBgAAAA==.',
Ny='Nyancat:BAAANQAECgcIEAAAAA==.',
Oo='Oojni:BAABNQAECn8YAAMHAAYK8hBEJQAIAQAHAAUK3glEJQAIAQAGAAYK8QeJuwD0AAAAAA==.',
Os='Ostin:BAAANQADCgEIAQAAAA==.',
Pa='Pantheon:BAAANQADCgMIBAAAAA==.',
Ph='Pharhar:BAABNQAECn8zAAMWAAoKOCOMEQBCAwAWAAoKOCOMEQBCAwAZAAEKTg5FmQE7AAAAAA==.',
Po='Poppachàdson:BAABNQAECn8YAAIHAAgKeB13EABiAgAHAAgKeB13EABiAgAAAA==.Poppadadson:BAAANQAECgcICQABNQAECggIGAAHAHgdAA==.',
Pr='Primex:BAAANQAECgYIDwAAAA==.',
Pu='Pukebucket:BAABNQAFFH8FAAIaAAUKKBDhAwD+AAAaAAUKKBDhAwD+AAAAAA==.Punished:BAAANQADCgEIAQAAAA==.Puscifer:BAAANQADCggIEAAAAA==.',
Qu='Qualil:BAAANQAECgcICwAAAA==.Quxxi:BAAANQADCgIIAgAAAA==.',
Ra='Ragewyrm:BAAANQADCgUIBQAAAA==.Raizel:BAAANQAECgIIAgABNQAECgoKTAANACAiAA==.Ravister:BAAANQAECgEIAQABNQAFFAUIDQAMANgZAA==.',
Re='Reinhart:BAABNQAECn8gAAIIAAkK2w3eXQB6AQAIAAkK2w3eXQB6AQAAAA==.Relic:BAACNQAFFH8PAAIbAAcKKAdoBgA6AQAbAAcKKAdoBgA6AQA1AAQKfzkAAxsACgq6HoAQAKkCABsACgq6HoAQAKkCAAgAAQrEFqnFAD0AAAAA.Reneia:BAABNQAECn89AAIIAAoKyiFvFgD6AgAIAAoKyiFvFgD6AgABNQABCgIIAgADAAAAAA==.Renk:BAABNQAECn8xAAIcAAgKVyVBGAD8AgAcAAgKVyVBGAD8AgAAAA==.',
Rh='Rhllor:BAAANQAECggIDwABNQAECgQIBgADAAAAAA==.Rhíza:BAABNQAECn8YAAIOAAYK4At8ZgAzAQAOAAYK4At8ZgAzAQAAAA==.',
Ro='Roughneck:BAAANQAECgYIDQAAAA==.',
Sa='Saeyl:BAAANQADCggIDgABNQAECgcICwADAAAAAA==.Samesarian:BAAANQADCgEIAQAAAA==.Sammie:BAEBNQAECn8aAAIdAAoKNhYJBwBPAgAdAAoKNhYJBwBPAgABNQAECggIEQADAAAAAA==.Sayl:BAABNQAECn8iAAQMAAYKJRHkNwBmAQAMAAYKJRHkNwBmAQAPAAUKJQNF1ACqAAAXAAQKsgZKGQCkAAABNQAECgcICwADAAAAAA==.',
Sc='Scallywinkle:BAAANQADCgQIBAAAAA==.',
Sh='Shaki:BAAANQADCgMIAwABNQAECgMIAwADAAAAAA==.Shamewow:BAACNQAFFH8WAAIGAAcKMxdVBwDlAQAGAAcKMxdVBwDlAQA1AAQKf0cAAgYACgpOHaIaALUCAAYACgpOHaIaALUCAAAA.Sheam:BAAANQAECgMIAwAAAA==.',
Si='Sicknnasty:BAACNQAFFH8WAAIIAAcKHBtrCwCeAQAIAAcKHBtrCwCeAQA1AAQKf2AAAwgACgo4I8QGAIsDAAgACgo4I8QGAIsDABwACAqlFqpQANEBAAAA.',
Sm='Smoguls:BAAANQADCgQIBAAAAA==.',
Sn='Snattch:BAAANQAECgEIAQAAAA==.',
So='Sos:BAAANQADCgQIBAAAAA==.',
Sp='Speed:BAAANQAECgIIAgAAAA==.Spicytuna:BAAANQADCgYIFAAAAA==.',
St='Starshopping:BAAANQADCgUICgABNQAECgoKRAALAAclAA==.',
Su='Sunari:BAAANQADCgUICgAAAA==.',
Ta='Taelium:BAACNQAFFH8KAAIaAAYK7hTUBQBCAQAaAAYK7hTUBQBCAQA1AAQKfywAAxoACgowIKMHAKkCABoACgowIKMHAKkCABkABwqRDEDVAHEBAAAA.Talrip:BAABNQAECn8gAAIeAAoK5hdNCABzAgAeAAoK5hdNCABzAgAAAA==.Tandsondsong:BAAANQAECgEIAgAAAA==.Tanfer:BAAANQAECgMIAwABNQAECgYICgADAAAAAA==.',
Th='Thalaneth:BAAANQAECgYICQAAAA==.Thalindra:BAAANQADCggIDwAAAA==.',
To='Toatem:BAAANQADCgUICAAAAA==.Torope:BAACNQAFFH8RAAIBAAcK/gpsEwAdAQABAAcK/gpsEwAdAQA1AAQKf0YAAwEACgpzIyMPAAIDAAEACgpzIyMPAAIDAB8AAgrzDxoJAEMAAAAA.',
Tr='Trappynomnom:BAAANQAECgIIAgAAAA==.Tree:BAAANQAFFAEIAgABNQAFFAIIBgAWADshAA==.',
Tz='Tzungxie:BAABNQAECn89AAMSAAoKxB7sEwC5AgASAAoKqh7sEwC5AgAgAAYKdRe3QQDEAQAAAA==.',
Uh='Uhohsocold:BAAANQADCgEIAgAAAA==.',
Un='Unholylord:BAACNQAFFH8NAAIMAAUK2BmyBQDXAQAMAAUK2BmyBQDXAQA1AAQKf0wABA8ACgovINMHAJcDAA8ACgovINMHAJcDAAwACgp1JqoAAIYDABcAAQr+GhQlAEQAAAAA.',
Va='Valinia:BAAANQADCgQIBAABNQAECgYICgADAAAAAA==.',
Vi='Vitali:BAAANQAFFAEIAQABNQAFFAUIDQAMANgZAA==.',
Wh='Whack:BAAANQADCgEIAgAAAA==.Whoa:BAAANQADCgYICwAAAA==.',
Wi='Wiigo:BAAANQAECgUICwABNQAECgoKTgAKAEAgAA==.',
Ye='Yearofspear:BAEANQAECgEIAQABNQAECggIEQADAAAAAA==.',
Yi='Yirnkal:BAAANQADCgEIAgAAAA==.',
Yo='Yogybear:BAAANQADCgEIAQAAAA==.',
Ys='Ystarian:BAACNQAFFH8GAAIhAAMKHwe7AwCtAAAhAAMKHwe7AwCtAAA1AAQKf0wAAyEACgrRHMoKAL8CACEACgrRHMoKAL8CACIABgrTEt8QACkBAAAA.',
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
