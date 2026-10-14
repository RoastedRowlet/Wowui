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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Hunter-Survival','Warlock-Destruction','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Shaman-Elemental','Evoker-Devastation','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Warrior-Protection','Druid-Guardian','Monk-Windwalker','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Evoker-Preservation','Monk-Brewmaster','Rogue-Assassination','Mage-Arcane','Mage-Frost','Evoker-Augmentation','Mage-Fire','Druid-Balance','Priest-Discipline','Hunter-Marksmanship','Shaman-Restoration','Warlock-Affliction','Warlock-Demonology','Shaman-Enhancement','Druid-Restoration',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abused:BAAANQADCgUIBQAAAA==.',
Ad='Adelaide:BAACNQAFFH8NAAIBAAUKyxgYDgCnAQABAAUKyxgYDgCnAQA1AAQKfyMAAwEACQoRISIZAA8DAAEACQoRISIZAA8DAAIAAQpWCj10ADsAAAE1AAUUBQgMAAMA6SQA.Adelesta:BAAANQAECgEIAQAAAA==.',
Ag='Aglovale:BAABNQAECn8pAAMEAAgKfyXCBABoAwAEAAgKfyXCBABoAwAFAAEKmhZAhwFIAAAAAA==.Agravaine:BAAANQADCgIIAgABNQAECggIKQAEAH8lAA==.',
Aj='Ajunlucky:BAACNQAFFH8GAAIGAAQKtQ3qAABTAQAGAAQKtQ3qAABTAQA1AAQKfy4AAgYACQqKHx0CACwDAAYACQqKHx0CACwDAAAA.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECggIKQAEAH8lAA==.Alexari:BAAANQADCggICwAAAA==.Alnilam:BAABNQAECn8hAAIHAAgKTg/+EQDlAQAHAAgKTg/+EQDlAQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
Ap='Appypie:BAAANQAECgcIDQAAAA==.',
Ar='Arbys:BAAANQAECggIDgAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAABNQAECn8oAAIIAAgKXyMLBQA6AwAIAAgKXyMLBQA6AwAAAA==.Armados:BAAANQAECgUIEgAAAA==.Aroxw:BAACNQAFFH8MAAIJAAUKBxOoEgCVAQAJAAUKBxOoEgCVAQA1AAQKfx8AAwkACQrtHvg8ANICAAkACQrtHvg8ANICAAoAAQoAAI8nAG0AAAAA.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athaal:BAAANQABCgQIBAAAAA==.Athineana:BAAANQAECgQIBAAAAA==.Atlim:BAAANQADCggIIgAAAA==.',
Ay='Aylinn:BAAANQAECgYIDwAAAA==.Aylira:BAAANQAECgEIAgAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwABNQADCggICwALAAAAAA==.',
Ba='Bad:BAAANQAECggICAAAAA==.Balfas:BAAANQADCgQIBAABNQAECgkJGgAMAB4YAA==.Ballsmasher:BAAANQADCggIEgAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECn8jAAIKAAgKACLwAwAHAwAKAAgKACLwAwAHAwAAAA==.Bettyspready:BAAANQAECgcIEwAAAA==.',
Bi='Bigmanooshki:BAAANQAECgEIAgAAAA==.Bigpoppapump:BAAANQAECgYJDQAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAABNQAECn8YAAINAAgKhgR0HwBbAQANAAgKhgR0HwBbAQAAAA==.',
Bl='Blackfoot:BAAANQAECgcIEQAAAA==.Blankjr:BAAANQAECgIIAwAAAA==.Blart:BAAANQAECgQIBAAAAA==.Blathnaid:BAAANQAECgUIBQABNQAFFAUIDAADAOkkAA==.Blightmoss:BAAANQAECgEIAQABNQAECgcIDgALAAAAAA==.Blindpov:BAACNQAFFH8FAAIOAAIKmyAaEwC/AAAOAAIKmyAaEwC/AAA1AAQKfzkAAw4ACQppJoUBAOMDAA4ACQppJoUBAOMDAA8ABwrDH6wqAOgBAAAA.',
Bo='Bodyodyodied:BAAANQADCgQIBAAAAA==.Bonquiquie:BAAANQAECgQIBAAAAA==.Boop:BAAANQADCggIDgAAAA==.Bouberry:BAAANQADCgcIDgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECn8aAAIOAAkKORlCJQBvAgAOAAkKORlCJQBvAgAAAA==.Breakerr:BAAANQAECgIIAgAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAABNQAECn8kAAIQAAgKKx7vKADCAgAQAAgKKx7vKADCAgAAAA==.Bubbly:BAABNQAECn8ZAAIFAAgKIBgoZgBkAgAFAAgKIBgoZgBkAgAAAA==.',
['Bë']='Bërshton:BAABNQAECn8VAAMGAAgK+xlyBwD7AQAGAAcKlBZyBwD7AQADAAMKIBRvGAHIAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAQAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECn8bAAIRAAgKSwowHQBpAQARAAgKSwowHQBpAQAAAA==.Cattle:BAABNQAECn8nAAISAAkKmRg9DgB7AgASAAkKmRg9DgB7AgAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Chowdk:BAAANQADCggICAAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECgcIDAAAAA==.',
Cl='Clawsofpeace:BAAANQAECggIDgAAAA==.',
Co='Constanse:BAAANQADCgYICgAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cy='Cylic:BAABNQAECn8fAAIIAAgKiSINCQDkAgAIAAgKiSINCQDkAgAAAA==.Cyrùsdh:BAAANQAECgUIBQAAAA==.',
Da='Daddiestouch:BAAANQAECgYIEQAAAA==.Dampundies:BAABNQAECn8WAAITAAgKYx2YFgCWAgATAAgKYx2YFgCWAgAAAA==.Dangerdream:BAABNQAECn8tAAQPAAkKDSExCgA2AwAPAAkKDSExCgA2AwAUAAUK1hKkGwD8AAAOAAEKFRXQiwBAAAAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Dartini:BAAANQADCgIIAgABNQAECgcIEgALAAAAAA==.Datsmywife:BAABNQAECn8oAAIVAAkKHhPWDABRAgAVAAkKHhPWDABRAgAAAA==.Davis:BAABNQAECn8eAAQWAAkKKx3rJACqAgAWAAkKKx3rJACqAgAXAAMKqBGtggCaAAAYAAEKWBFEwwA+AAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.',
De='Deadasice:BAAANQADCgEIAQABNQADCgIIAgALAAAAAA==.Demonknuts:BAAANQAECggICAAAAA==.Derpdragon:BAABNQAECn8xAAIZAAkK6R7HCgD2AgAZAAkK6R7HCgD2AgAAAA==.Derppriest:BAAANQADCggICAABNQAECgkJMQAZAOkeAA==.Deviiarrc:BAACNQAFFH8NAAIZAAUKWw74CwBYAQAZAAUKWw74CwBYAQA1AAQKfzUAAhkACQo7I9AEAGEDABkACQo7I9AEAGEDAAAA.Devviarc:BAAANQADCggICwABNQAFFAUIDQAZAFsOAA==.',
Di='Dibgargargad:BAAANQAECggICAAAAA==.',
Dl='Dlamb:BAAANQAECgQIDwABNQAECgUICQALAAAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAABNQAECn8VAAMKAAgKYR1ZCgAjAgAKAAYKJyBZCgAjAgAJAAMKBhiqCgHBAAAAAA==.',
Dr='Dracar:BAABNQAECn8lAAIFAAkKTCOpDgCQAwAFAAkKTCOpDgCQAwAAAA==.Drmmrfist:BAABNQAECn8bAAIaAAgKURBkFACaAQAaAAgKURBkFACaAQAAAA==.Drmmrwartwo:BAAANQAECgYIBgAAAA==.',
Dw='Dwippietiggs:BAABNQAECn8iAAIFAAkKEhwwRwC8AgAFAAkKEhwwRwC8AgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAFFAYIGgAQAHgmAA==.Earthfeather:BAAANQADCggIDwAAAA==.Easymac:BAAANQADCgIJAwABNQAECgkJGgAOADkZAA==.',
Ee='Eetee:BAAANQAECgQICwABNQAECggIIAAEAKcLAA==.',
Eh='Ehemingway:BAABNQAECn8UAAIDAAQKKBlr5AAzAQADAAQKKBlr5AAzAQAAAA==.',
El='Eleabuser:BAAANQAECgEIAQAAAA==.Elysin:BAAANQAFFAEIAQABNQAFFAUIDAADAOkkAA==.',
Em='Emberstone:BAAANQAECgQIBAAAAA==.Emoux:BAAANQADCgYIBgAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAABNQAECn8ZAAIbAAgKAg8sOQDqAQAbAAgKAg8sOQDqAQAAAA==.Ereye:BAABNQAECn8YAAIIAAcKHhY/HwDTAQAIAAcKHhY/HwDTAQAAAA==.',
Es='Esstina:BAAANQAECgIIAgAAAA==.Estuku:BAABNQAECn8bAAIcAAcK8wl9/QCPAQAcAAcK8wl9/QCPAQAAAA==.',
Et='Etatoned:BAAANQADCgQIBAABNQAECggIIAAEAKcLAA==.Etengaged:BAABNQAECn8gAAIEAAgKpwtpLgBmAQAEAAgKpwtpLgBmAQAAAA==.Ethavoc:BAAANQAECgcIDgABNQAECggIIAAEAKcLAA==.',
Ev='Evrae:BAABNQAECn8fAAIIAAkKdhYnDwCGAgAIAAkKdhYnDwCGAgAAAA==.',
Ex='Extragrace:BAAANQADCgcIBwAAAA==.',
Ey='Eyeofjazz:BAAANQABCggICQAAAA==.',
Fa='Faithshand:BAABNQAECn8YAAIBAAgKOAjygwCGAQABAAgKOAjygwCGAQAAAA==.Fatkow:BAAANQAECggIBQABNQAECgkJLAAWABImAA==.',
Fe='Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQICQAAAA==.Feio:BAAANQADCggIBAAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFH8kAAMcAAgKFh6yCAA1AgAcAAYKaxyyCAA1AgAdAAIKbSGRBADIAAA1AAQKfyMAAhwACQrOIflSANoCABwACQrOIflSANoCAAAA.Finkler:BAABNQAECn8nAAMcAAkKnB4pewCIAgAcAAkKixspewCIAgAdAAIK3yRPJADIAAABNQAFFAgIJAAcABYeAA==.Firedanny:BAAANQAECgEIAQAAAA==.Fistsofpeace:BAAANQAECgYJCwABNQAECggIDgALAAAAAA==.',
Fl='Flameshock:BAABNQAECn8oAAMdAAkKwg+HDwCtAQAcAAkKJA18sAAgAgAdAAgKXg+HDwCtAQAAAA==.',
Fo='Forcepull:BAAANQAECgUIDAABNQAECgkJKwATAJESAA==.',
Fr='Frankda:BAAANQADCgIIAgAAAA==.Frawstshawkk:BAAANQAECggICAAAAA==.Friendshaped:BAAANQAECgMIAwABNQAFFAYKFQADADAiAA==.Friendship:BAAANQADCgEIAQAAAA==.Frigidbeach:BAAANQAECgEIAQAAAA==.',
Gh='Ghale:BAAANQADCggIFgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFH8ZAAMNAAgKoxuIAwC1AQANAAUKMR6IAwC1AQAeAAUKahkuBACbAQA1AAQKfx8AAw0ACQr3IZAOAHMCAA0ACQoJHpAOAHMCAB4AAwonJr0OAFQBAAAA.Gloreb:BAAANQAFFAQIBAAAAA==.',
Go='Goomi:BAAANQAECgYIDAAAAA==.Gordef:BAABNQAECn8YAAMdAAgKuhVUDADzAQAdAAgKFBVUDADzAQAfAAYKPw+tBABUAQAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMIBgAAAA==.Grismago:BAAANQAECgEIAgAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgcIEgAAAA==.',
Ha='Haakon:BAAANQADCgUIBQAAAA==.Hanaya:BAAANQAECgUIBQAAAA==.Harrowing:BAABNQAECn9EAAIQAAkKfh66GAAVAwAQAAkKfh66GAAVAwAAAA==.Haurt:BAABNQAECn8jAAIgAAgKhgoUUgCPAQAgAAgKhgoUUgCPAQAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAABNQAECn8VAAIYAAcKyBnjPgACAgAYAAcKyBnjPgACAgAAAA==.',
Hi='Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAABNQAECn8XAAMQAAkK0hoWMACkAgAQAAkK0hoWMACkAgAFAAUKER32tgCqAQAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAAANQADCgMIAwAAAA==.Hotmess:BAAANQAECgUIDwAAAA==.',
Hu='Hussongs:BAAANQAECgQIBAAAAA==.',
['Hô']='Hôly:BAAANQAECgcIDgAAAA==.',
In='Insanê:BAAANQAECggIDwABNQAECgkJLAATAJ8TAA==.Insañe:BAABNQAECn8sAAMTAAkKnxMwHwAzAgATAAkKnxMwHwAzAgAaAAEKkRAdMQAxAAAAAA==.Invi:BAAANQAECgYICQAAAA==.',
Ir='Ironbeef:BAAANQAECgYICQAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICgALAAAAAA==.Jadengras:BAAANQAECgQIBAAAAA==.Jasminetea:BAAANQADCgcIBwAAAA==.Jayylols:BAAANQAECgYIDQAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAAANQAECgYIEgAAAA==.',
['Jë']='Jësus:BAABNQAECn8kAAMhAAkKthL3CgCTAQABAAgKFRPcYAD7AQAhAAcK1RH3CgCTAQAAAA==.',
Ka='Kalandaelis:BAAANQADCggJFQAAAA==.Kaldren:BAAANQADCgYIFAAAAA==.Kalel:BAAANQAECgUIDAAAAA==.Karmakazie:BAAANQAECgQICQAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAABNQAECn8fAAIDAAcK8BdodgAgAgADAAcK8BdodgAgAgAAAA==.Kazraghand:BAABNQAECn8pAAIGAAkKPBAiBQB2AgAGAAkKPBAiBQB2AgAAAA==.',
Ke='Keetanah:BAAANQAECgQIBAAAAA==.Kei:BAACNQAFFH8HAAIPAAMKSg7bDQDHAAAPAAMKSg7bDQDHAAA1AAQKfyUAAw8ACQoKGooXAJ8CAA8ACQoKGooXAJ8CAA4AAQrpDNiNADsAAAAA.Kelsio:BAABNQAECn8fAAIDAAkKpRfWTQCCAgADAAkKpRfWTQCCAgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQAECgEJAQAAAA==.',
Kh='Kharos:BAABNQAECn8pAAIBAAkKuhA+UQAsAgABAAkKuhA+UQAsAgAAAA==.',
Ki='Kikeo:BAAANQAECggIDQABNQAFFAMIBwAPAEoOAA==.Kinks:BAABNQAECn8UAAIOAAYKlhEdTABqAQAOAAYKlhEdTABqAQAAAA==.Kirkoth:BAAANQAECgEIAQAAAA==.',
Kn='Knuah:BAAANQADCgYIBgABNQAECgkJHQACANoUAA==.Knuts:BAAANQAECggIBwAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kovah:BAACNQAFFH8FAAIbAAUKDw/0BwCOAQAbAAUKDw/0BwCOAQA1AAQKfyAAAhsACQqGGq8KADMDABsACQqGGq8KADMDAAAA.Kowtagion:BAABNQAECn8sAAMWAAkKEibHBACoAwAWAAkKEibHBACoAwAYAAEKeiXBsQBjAAAAAA==.',
Kp='Kpopped:BAAANQAECgQICAAAAA==.',
Kr='Krahz:BAAANQAECgUIDAAAAA==.Krelsh:BAABNQAECn8bAAQiAAgKsxxhMQC+AQAiAAcKAxthMQC+AQADAAIKciAcIAGyAAAGAAIKYAGwEQBLAAABNQAFFAIIBQAcALsTAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYICQAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kybrickerson:BAAANQAECgEIAQAAAA==.Kyruutos:BAAANQAECgMICQAAAA==.',
['Kí']='Kítkat:BAABNQAECn8iAAIjAAgKrB0gKgC5AgAjAAgKrB0gKgC5AgAAAA==.',
La='Laziza:BAAANQAECgEIAQAAAA==.',
Le='Leibowitzy:BAABNQAECn8rAAMTAAkKkRKqJAD7AQATAAkKWhKqJAD7AQAaAAUKCxNbGABZAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAQAAAA==.Lenastin:BAAANQADCggICAABNQAFFAEIBgAQAHomAA==.Letra:BAAANQADCgMIAwAAAA==.Lexstrasza:BAAANQABCgIIAgAAAA==.',
Lh='Lhehitman:BAABNQAECn8fAAIdAAkK3SCaAgA4AwAdAAkK3SCaAgA4AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgQIBQAAAA==.Lightshax:BAABNQAECn8cAAIQAAgKtQ+ocADDAQAQAAgKtQ+ocADDAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAABNQAECn8aAAIUAAgK/AxcEQCXAQAUAAgK/AxcEQCXAQAAAA==.Liv:BAAANQADCgIIAgAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQADCgEIAQAAAA==.',
Lu='Luckydog:BAAANQAECgUICAAAAA==.Ludey:BAABNQAECn80AAMkAAkKXRkZBACiAgAkAAkKXRkZBACiAgAlAAEKVRRANAFGAAAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lumiya:BAAANQAECgEIAQAAAA==.Lutray:BAAANQAECgcIEAAAAA==.',
Ma='Makaveleli:BAAANQAECgUIBQAAAA==.Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECn8tAAIBAAkKmhGvSABIAgABAAkKmhGvSABIAgAAAA==.Marodd:BAABNQAECn8YAAICAAgKxCBrFQCyAgACAAgKxCBrFQCyAgAAAA==.Mashîra:BAACNQAFFH8NAAIDAAYKvxyvAwAhAgADAAYKvxyvAwAhAgA1AAQKfysAAwMACQrxJXQGAKoDAAMACQq1JXQGAKoDACIABgr1H5MiADYCAAAA.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQAECgQIBAAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECn81AAQjAAkKOh6sHQDzAgAjAAkKOh6sHQDzAgAmAAEKAADDNAA6AAAMAAEKAABTOwEuAAAAAA==.Mekuro:BAAANQAECgQICgAAAA==.Merihem:BAAANQADCgUICAAAAA==.Meshnee:BAAANQAECgMIAwAAAA==.Mewfasa:BAAANQADCggICAAAAA==.',
Mi='Mia:BAAANQAECgcIDwAAAA==.Milize:BAABNQAECn8hAAIFAAgKOyC/SgCxAgAFAAgKOyC/SgCxAgAAAA==.Minasuzune:BAABNQAECn8SAAMDAAcK6R87ZwBDAgADAAcK6R87ZwBDAgAiAAIK9AxFdABkAAAAAA==.Miney:BAAANQADCgYICQAAAA==.Minus:BAAANQADCgIIAgAAAA==.',
Mo='Moondotter:BAAANQAECgQIBAABNQAECgQIBgALAAAAAA==.Moongoddess:BAAANQAECgQIBgAAAA==.Moonslayer:BAAANQAECgcIEQAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.',
My='Mybanknoturs:BAAANQABCgQIBAAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAFFAYIDQADAL8cAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAQABNQAFFAYIDQADAL8cAA==.Måshîrå:BAAANQAECgYICQABNQAFFAYIDQADAL8cAA==.',
Na='Nakor:BAABNQAECn8bAAIcAAcK3QMLLwE6AQAcAAcK3QMLLwE6AQAAAA==.Nalian:BAAANQAECgYJDgAAAA==.Nalliella:BAABNQAECn8bAAIKAAcKLBJTDwC0AQAKAAcKLBJTDwC0AQAAAA==.Natashers:BAAANQADCgcIDAAAAA==.',
Ne='Neenzy:BAAANQAECgYIDgAAAA==.Nefeli:BAABNQAECn8sAAIeAAkKBBdnBQCPAgAeAAkKBBdnBQCPAgAAAA==.Nelinne:BAAANQAECgIIAwAAAA==.Nellevene:BAAANQAECgYIEAAAAA==.Nestia:BAAANQAECgQIBgAAAA==.Never:BAACNQAFFH8HAAMHAAMKDBjMDACgAAAlAAIKexgYLQCjAAAHAAIKIBXMDACgAAA1AAQKfyoAAyUACQqJIj44AKgCACUACApbIj44AKgCAAcABQpHHg0dAIQBAAAA.',
Ni='Nightshade:BAABNQAECn8xAAIDAAkKVhvmLgDeAgADAAkKVhvmLgDeAgAAAA==.Nimbus:BAAANQAECgcICAAAAA==.Nix:BAAANQADCgYIBgAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgcIEQAAAA==.',
Oc='Ocllo:BAABNQAECn8cAAIEAAgKQhNuHQD8AQAEAAgKQhNuHQD8AQAAAA==.',
Og='Oghealz:BAAANQAECgQICQAAAA==.',
Oj='Ojo:BAAANQAECgcIEgAAAA==.',
On='Oniana:BAABNQAECn8gAAIiAAcKlQrYOwBtAQAiAAcKlQrYOwBtAQAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAECgkJKAAgAIkRAA==.',
Ow='Owwmyballs:BAAANQADCgMIAwAAAA==.',
Oz='Ozygo:BAAANQADCgcIDAAAAA==.',
Pa='Pagamas:BAACNQAFFH8NAAIcAAUKkRYmGQCrAQAcAAUKkRYmGQCrAQA1AAQKfyQAAxwACQrrHn1WANMCABwACQrrHn1WANMCAB0AAgqLEQU3AF4AAAAA.Palandari:BAAANQAECgUICAAAAA==.Pandawan:BAAANQAECgMICAAAAA==.Pandormu:BAAANQAECgQIBAABNQAECggICgALAAAAAA==.Panter:BAAANQAECggICgAAAA==.Paperplanes:BAAANQAECgEIAQAAAA==.',
Pe='Pebble:BAAANQAECgQICQAAAA==.',
Ph='Phodoe:BAABNQAECn8ZAAInAAgKbwqSMwB5AQAnAAgKbwqSMwB5AQAAAA==.',
Pi='Pinquisitor:BAAANQADCgQIAQABNQAECgMICAALAAAAAA==.',
Pl='Platewinslet:BAAANQAECgIIAgAAAA==.Playne:BAAANQAECgUICwAAAA==.',
Po='Pokeureyeout:BAAANQAECgUIDQAAAA==.Port:BAAANQAECgUIBgABNQAECgcIDgALAAAAAA==.',
Pr='Preaced:BAAANQAECgYIBgABNQAECggIDgALAAAAAA==.Prodyne:BAABNQAECn81AAIcAAkKRxQUdwCPAgAcAAkKRxQUdwCPAgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECgYIEQALAAAAAA==.',
Qa='Qariwarmi:BAAANQAECgIIAgAAAA==.',
Qu='Quag:BAAANQADCgUIBQAAAA==.Quiettreader:BAABNQAECn8rAAIdAAkKmhgwBQDDAgAdAAkKmhgwBQDDAgAAAA==.Quokka:BAAANQAECgMIBQAAAA==.',
Ra='Raegwin:BAAANQAECgUIDAAAAA==.Raidboss:BAAANQAECgcIEAAAAA==.',
Re='Redeath:BAAANQAECgQIBgAAAA==.Redirect:BAAANQAECgIIAgABNQAECgQIBgALAAAAAA==.Redonculous:BAABNQAECn8dAAICAAkK2hQ3HgBLAgACAAkK2hQ3HgBLAgAAAA==.Redpool:BAABNQAECn8qAAIjAAkK1w+cXAD2AQAjAAkK1w+cXAD2AQAAAA==.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECn8mAAIPAAcK7CD4FwCbAgAPAAcK7CD4FwCbAgAAAA==.Revansong:BAAANQADCgYICgABNQAECggIKAAIAF8jAA==.Reymnant:BAAANQAECgIIAwAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.',
Ro='Ronx:BAAANQAECgYIDAAAAA==.Roxxiloxxi:BAABNQAECn8kAAMHAAkKfgaOGACmAQAHAAkKfgaOGACmAQAlAAIKDAL9MwFHAAAAAA==.',
Ru='Rudeboy:BAABNQAECn8nAAIlAAgKDxqTUwBXAgAlAAgKDxqTUwBXAgAAAA==.Rushu:BAACNQAFFH8FAAIcAAIKuxMRQwChAAAcAAIKuxMRQwChAAA1AAQKfygAAhwACQpHGeFZAMwCABwACQpHGeFZAMwCAAAA.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECn8wAAMQAAkKchUJQABiAgAQAAkKchUJQABiAgAFAAcKYQpz3ABcAQAAAA==.Sagitta:BAAANQADCgcIBwABNQAECgcIEgALAAAAAA==.Sahria:BAAANQAECgQIBAAAAA==.Samlosco:BAAANQAECgYICQAAAA==.Sapphpal:BAAANQAECgYICAABNQAECgcICAALAAAAAA==.Sarhia:BAAANQAECgMIAwAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgALAAAAAA==.',
Sc='Schizology:BAAANQADCggIEAAAAA==.Schnoze:BAAANQAECgQIDgAAAA==.',
Se='Sebekuul:BAAANQADCgYIBgAAAQ==.Selfie:BAAANQABCgIIAgAAAA==.Selys:BAACNQAFFH8IAAIcAAQKkAonLQAfAQAcAAQKkAonLQAfAQA1AAQKfy8AAxwACQoBE96FAHICABwACQoBE96FAHICAB0AAgr1BtE4AFgAAAAA.Sence:BAAANQABCgQIBAAAAA==.Sepheturix:BAAANQAECgUIBQAAAA==.Sephurik:BAACNQAFFH8RAAMcAAQKLQ60KAA8AQAcAAQKLQ60KAA8AQAdAAEKXQDoFABBAAA1AAQKfz0AAxwACQpGI18qADsDABwACQqRIV8qADsDAB0AAgpTHhMpAKsAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowswife:BAAANQADCgcIBwAAAA==.Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQADCggIDQAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shammuri:BAAANQADCgQIBAAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawnalenee:BAAANQAECgUICQAAAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiriax:BAAANQAECgIJBAAAAA==.Shiv:BAAANQAECggIAgAAAA==.',
Si='Sidisi:BAAANQAECgcIBwABNQAECgkJHgAiALogAA==.Sikanda:BAABNQAECn8VAAMWAAgKtB0CIwC2AgAWAAgKtB0CIwC2AgAXAAIKuhRgiQCEAAABNQAECgkJHgAiALogAA==.Silvea:BAAANQAECgYIEgAAAA==.Silvett:BAAANQAECgEIAQAAAA==.Sinara:BAAANQAECgQIBQAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECn8mAAICAAkKVh8IDQAYAwACAAkKVh8IDQAYAwAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Skillertank:BAAANQADCggIDwAAAA==.Sky:BAABNQAECn8nAAIcAAkK5CJ2FQB9AwAcAAkK5CJ2FQB9AwAAAA==.Skyelf:BAABNQAECn8gAAIDAAgK2QumiwDvAQADAAgK2QumiwDvAQAAAA==.',
Sl='Slimshadow:BAAANQABCgIJAgAAAA==.Sloppysloosh:BAAANQAECgYIDAAAAA==.',
Sm='Smallpox:BAAANQADCgUIDgAAAA==.Smokebreak:BAAANQADCggICAAAAA==.',
Sn='Snooflepoof:BAABNQAECn8vAAIjAAkKORtGIADmAgAjAAkKORtGIADmAgAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAcIIQAmADUiAA==.Solunara:BAAANQADCgUIBQABNQAECgcIDgALAAAAAA==.',
Sp='Spectrecles:BAABNQAECn8oAAIgAAkKiRHEMgBLAgAgAAkKiRHEMgBLAgAAAA==.Spectrecless:BAAANQAECgMIAwABNQAECgkJKAAgAIkRAA==.Speez:BAABNQAECn8aAAIDAAcKshWneAAaAgADAAcKshWneAAaAgAAAA==.Sphester:BAAANQADCgUIBQAAAA==.',
St='Stablehand:BAAANQAECgUIDQAAAA==.Steve:BAACNQAFFH8QAAIMAAQKJAmrEABaAQAMAAQKJAmrEABaAQA1AAQKfzQAAwwACQrrIssTAFEDAAwACQrrIssTAFEDACMAAQo+AscgASkAAAAA.Stonedfel:BAABNQAECn8dAAIOAAgKWRJhOADqAQAOAAgKWRJhOADqAQAAAA==.',
Su='Sunhoof:BAAANQAECgcIDgAAAA==.Supahotvile:BAABNQAECn8XAAIbAAkKeA8lKwA4AgAbAAkKeA8lKwA4AgAAAA==.',
Sy='Syx:BAAANQADCgYIBgAAAA==.',
['Sø']='Sørrow:BAABNQAECn8ZAAIPAAcKqA9KNQCUAQAPAAcKqA9KNQCUAQAAAA==.',
Ta='Tabi:BAABNQAECn8dAAMdAAgKQQecFwA8AQAdAAgKBQecFwA8AQAcAAYK9QGBeAHKAAAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggJDQAAAA==.Tankoromma:BAAANQADCgUIBQAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwABNQAECgQICAALAAAAAA==.',
Te='Test:BAAANQAECggJAQAAAA==.',
Th='Thedawg:BAAANQADCgEIAQAAAA==.Thedayman:BAAANQADCggICAAAAA==.Thetaint:BAABNQAECn8mAAIbAAkKzSN9BACLAwAbAAkKzSN9BACLAwAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAACNQAFFH8MAAIDAAUK6SR3BwDTAQADAAUK6SR3BwDTAQA1AAQKfyEAAwMACQouI2MVAEUDAAMACQouI2MVAEUDACIAAQpAGZp/AEEAAAAA.Tiplar:BAAANQAECgQIBAABNQAECgkJJgACAFYfAA==.',
To='Totemofpeace:BAAANQADCggIEAABNQAECggIDgALAAAAAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Trentlock:BAACNQAFFH8HAAQlAAMK6wSlNQCIAAAlAAIK0QSlNQCIAAAHAAEKBAX4IgBEAAAkAAEKAAAYEgA+AAA1AAQKfywAAyUACQqXGiZRAF4CACUACQqeEyZRAF4CAAcABAoyISYhAGYBAAAA.Tristae:BAAANQAECgUICQAAAA==.',
Ts='Tsu:BAAANQAECgcIDQAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unholynavi:BAAANQAECgEIAQAAAA==.Unstablesha:BAAANQAECgUIBgAAAA==.',
Ut='Utilities:BAAANQADCggICAAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAACNQAFFH8JAAMWAAQKEBOuEQDtAAAWAAMKEBOuEQDtAAAYAAEKAAAUNgAlAAA1AAQKfy0AAhYACQq9IX0VAAwDABYACQq9IX0VAAwDAAAA.',
Vd='Vdomil:BAAANQABCgQIBAAAAA==.',
Vi='Via:BAAANQADCgYICgAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vil:BAACNQAFFH8eAAICAAgKghqvAAD8AgACAAgKghqvAAD8AgA1AAQKfygAAgIACQrCJjUCAL0DAAIACQrCJjUCAL0DAAAA.Vilonus:BAABNQAECn8fAAIlAAcK4hALkgC0AQAlAAcK4hALkgC0AQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwABNQAECgkJJgACAFYfAA==.',
Vo='Voidbwoy:BAAANQADCggIEwAAAA==.Volairis:BAAANQAECgQIAgABNQAECgkJHwAVAFAeAA==.Voy:BAABNQAECn8YAAIGAAgKjAgJCQCvAQAGAAgKjAgJCQCvAQAAAA==.',
Vu='Vulpes:BAAANQADCggICAAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
We='Weezy:BAABNQAECn8ZAAMCAAgKkA2vNwBkAQACAAcKbgqvNwBkAQABAAYK2wVkrQAIAQAAAA==.',
Wi='Williie:BAAANQAECgcICwAAAA==.Withengar:BAAANQAECgYIBQAAAA==.',
Wu='Wuoshi:BAAANQAECgQICAAAAA==.Wuuzzyy:BAABNQAECn8hAAIgAAkKxRGSNgA0AgAgAAkKxRGSNgA0AgAAAA==.',
Xa='Xaliko:BAAANQAECgcICgAAAA==.Xanbaran:BAABNQAECn81AAIBAAkKiQrsbADTAQABAAkKiQrsbADTAQAAAA==.',
Xi='Xiphus:BAAANQAECgIIAgAAAA==.',
Xy='Xyrters:BAAANQADCgIIAgAAAA==.Xyrtrew:BAACNQAFFH8KAAIjAAUKnCBbBwDeAQAjAAUKnCBbBwDeAQA1AAQKfy4AAyMACQr0ItIPAEQDACMACQr0ItIPAEQDAAwAAQoAALweAUwAAAAA.',
Ya='Yahenni:BAABNQAECn8eAAMiAAkKuiDsFAC1AgAiAAgKFx7sFAC1AgADAAgKYxcIYgBPAgAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yuki:BAAANQAECgYIBgAAAA==.Yukki:BAAANQAECggIBgAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAAANQAECgcIEgAAAA==.',
Ze='Zerk:BAABNQAECn8XAAIJAAkKYQKeAAHVAAAJAAkKYQKeAAHVAAAAAA==.',
Zu='Zurxes:BAAANQADCgEIAQAAAA==.',
Zy='Zynmonk:BAAANQAECgMIAwAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
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
