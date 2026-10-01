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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Protection','Hunter-Survival','Warlock-Destruction','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Protection','Druid-Guardian','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Evoker-Preservation','Monk-Brewmaster','Paladin-Retribution','Paladin-Holy','Mage-Frost','Mage-Arcane','Monk-Windwalker','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Hunter-Marksmanship','Shaman-Restoration','Warlock-Affliction','Shaman-Enhancement','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abused:BAAANQADCgUIBQAAAA==.',
Ad='Adelaide:BAACNQAFFIEFAAIBAAMKsxKTEgACAQABAAMKsxKTEgACAQA1AAQKgSAAAwEACQoFIZkPACEDAAEACQoFIZkPACEDAAIAAQpWCo9bAEAAAAE1AAQKCQkbAAMA/yIA.',
Ag='Aglovale:BAABNQAECoEcAAIEAAgK5iSjAwBgAwAEAAgK5iSjAwBgAwAAAA==.Agravaine:BAAANQADCgIIAgABNQAECggIHAAEAOYkAA==.',
Aj='Ajunlucky:BAABNQAECoEgAAIFAAkKJB4DAgAEAwAFAAkKJB4DAgAEAwAAAA==.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECggIHAAEAOYkAA==.Alexari:BAAANQADCggICwAAAA==.Alnilam:BAABNQAECoEYAAIGAAcKLRGEEwDHAQAGAAcKLRGEEwDHAQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
Ar='Arbys:BAAANQAECggIDAAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAABNQAECoEZAAIHAAcKgh4nDwBoAgAHAAcKgh4nDwBoAgAAAA==.Armados:BAAANQAECgUICQAAAA==.Aroxw:BAABNQAECoEaAAMIAAkKZh/2KgDjAgAIAAkKLB/2KgDjAgAJAAEKXSX8HgBuAAAAAA==.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athaal:BAAANQABCgQJBAAAAA==.Atlim:BAAANQADCgcIEwAAAA==.',
Ay='Aylinn:BAAANQAECgYIDwAAAA==.Aylira:BAAANQAECgEIAgAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwABNQADCggICwAKAAAAAA==.',
Ba='Bad:BAAANQAECggICAAAAA==.Balfas:BAAANQADCgQIBAABNQAECggIEwAKAAAAAA==.Ballsmasher:BAAANQADCggIEgAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECoEWAAIJAAgKcxo2BQCBAgAJAAgKcxo2BQCBAgAAAA==.Bettyspready:BAAANQAECgYICAAAAA==.',
Bi='Bigmanooshki:BAAANQAECgEIAgAAAA==.Bigpoppapump:BAAANQAECgYJDQAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAAANQAECgYIEwAAAA==.',
Bl='Blackfoot:BAAANQAECgcIDgAAAA==.Blankjr:BAAANQAECgEIAQAAAA==.Blart:BAAANQADCgYJBgAAAA==.Blathnaid:BAAANQAECgUIBQABNQAECgkJGwADAP8iAA==.Blightmoss:BAAANQAECgEIAQABNQAECgUICAAKAAAAAA==.Blindpov:BAABNQAECoEvAAMLAAkK6iXjAADsAwALAAkK6iXjAADsAwAMAAcKPSA8IAAQAgAAAA==.',
Bo='Bodyodyodied:BAAANQADCgQJBAAAAA==.Bonquiquie:BAAANQADCgYICQAAAA==.Boop:BAAANQADCggIDgAAAA==.Bouberry:BAAANQADCgcIDgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECoEXAAILAAgKIxk8IwA1AgALAAgKIxk8IwA1AgAAAA==.Breakerr:BAAANQAECgEIAQAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAAANQAECgUIEQAAAA==.Bubbly:BAAANQAECgcIEAAAAA==.',
['Bë']='Bërshton:BAABNQAECoEVAAMFAAgKURpBBQAiAgAFAAcK7xdBBQAiAgADAAMKIBTc3ADXAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAQAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECoEYAAINAAcKIQoaGQBCAQANAAcKIQoaGQBCAQAAAA==.Cattle:BAABNQAECoEeAAIOAAgKBhqACgBVAgAOAAgKBhqACgBVAgAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Chowdk:BAAANQADCggICAAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECgUIBgAAAA==.',
Cl='Clawsofpeace:BAAANQAECgcIBwAAAA==.',
Co='Constanse:BAAANQADCgMIBQAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cy='Cylic:BAABNQAECoEfAAIHAAgKNCIfBgANAwAHAAgKNCIfBgANAwAAAA==.Cyrùsdh:BAAANQADCgYIBgABNQAECgIIAgAKAAAAAA==.',
Da='Daddiestouch:BAAANQAECgUIBwAAAA==.Dampundies:BAAANQAECgYICQAAAA==.Dangerdream:BAABNQAECoEmAAMMAAgK5iHMCwAFAwAMAAgK5iHMCwAFAwAPAAUKChNOEwAPAQAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Dartini:BAAANQADCgIIAgABNQAECgcJDgAKAAAAAA==.Datsmywife:BAABNQAECoEjAAIQAAgKLxOrCgAfAgAQAAgKLxOrCgAfAgAAAA==.Davis:BAABNQAECoEbAAQRAAgKvR5YHACeAgARAAgKvR5YHACeAgASAAMKuBEnYgCgAAATAAEKWBFUpQBBAAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.',
De='Deadasice:BAAANQADCgEIAQAAAA==.Derpdragon:BAABNQAECoEsAAIUAAkK9x34CAD0AgAUAAkK9x34CAD0AgAAAA==.Deviiarrc:BAACNQAFFIEFAAIUAAIKYBGpDgCiAAAUAAIKYBGpDgCiAAA1AAQKgS8AAhQACQo7IyoDAHcDABQACQo7IyoDAHcDAAAA.Devviarc:BAAANQADCggICwABNQAFFAIIBQAUAGARAA==.',
Di='Dibgargargad:BAAANQAECgYIBgAAAA==.',
Dl='Dlamb:BAAANQAECgQICQAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAAANQAECgYIDgAAAA==.',
Dr='Dracar:BAAANQAECgcIEwAAAA==.Drmmrfist:BAABNQAECoEYAAIVAAcK8g+fEgB1AQAVAAcK8g+fEgB1AQAAAA==.',
Dw='Dwippietiggs:BAABNQAECoEZAAIWAAgKBxmqWAA5AgAWAAgKBxmqWAA5AgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAFFAUIDwAXAH4mAA==.Earthfeather:BAAANQADCgcIBwAAAA==.Easymac:BAAANQADCgIJAwABNQAECggIFwALACMZAA==.',
Ee='Eetee:BAAANQAECgMJBQABNQAECgYIEgAKAAAAAA==.',
Eh='Ehemingway:BAAANQAECgQICwAAAA==.',
El='Elysin:BAAANQAECgIIAgABNQAECgkJGwADAP8iAA==.',
Em='Emberstone:BAAANQADCgYJDwAAAA==.Emoux:BAAANQADCgYIBgAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAAANQAECgYIEwAAAA==.Ereye:BAABNQAECoEYAAIHAAcKjhQ7GQDsAQAHAAcKjhQ7GQDsAQAAAA==.',
Es='Esstina:BAAANQAECgIIAgAAAA==.Estuku:BAAANQAECgYIEgAAAA==.',
Et='Etatoned:BAAANQADCgQIBAABNQAECgYIEgAKAAAAAA==.Etengaged:BAAANQAECgYIEgAAAA==.Ethavoc:BAAANQAECgUIBQABNQAECgYIEgAKAAAAAA==.',
Ev='Evrae:BAABNQAECoEbAAIHAAgKthMqEgA/AgAHAAgKthMqEgA/AgAAAA==.',
Ex='Extragrace:BAAANQADCgcIBwAAAA==.',
Ey='Eyeofjazz:BAAANQABCgYIBgAAAA==.',
Fa='Faithshand:BAAANQAECgYIEwAAAA==.Fatkow:BAAANQAECgQIBAABNQAECgkJIQARAOglAA==.',
Fe='Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQIBwAAAA==.Feio:BAAANQADCggIBAAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFIEYAAMYAAcKLxdNAgDIAAAZAAUK+BOtDwCrAQAYAAIKOR9NAgDIAAA1AAQKgR4AAhkACQo9IBRFANcCABkACQo9IBRFANcCAAAA.Finkler:BAABNQAECoEnAAMZAAkKgx6ZUwCwAgAZAAkKIByZUwCwAgAYAAIK3yQVGwDUAAABNQAFFAcIGAAYAC8XAA==.Firedanny:BAAANQAECgEIAQAAAA==.Fistsofpeace:BAAANQAECgYJCwABNQAECgcIBwAKAAAAAA==.',
Fl='Flameshock:BAABNQAECoEfAAMYAAgKwRDPCQDgAQAZAAgKlAwYqgDjAQAYAAgKEBDPCQDgAQAAAA==.',
Fo='Forcepull:BAAANQAECgUIBwABNQAECgcIGQAaANEUAA==.',
Fr='Friendshaped:BAAANQAECgMIAwABNQAFFAUKCgADAFUgAA==.Friendship:BAAANQADCgEIAQAAAA==.Frigidbeach:BAAANQAECgEIAQAAAA==.',
Gh='Ghale:BAAANQADCggIDgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFIEWAAMbAAcKzh0AAgDTAQAbAAUKBxwAAgDTAQAcAAQK0h1FAwBOAQA1AAQKgRoAAxsACQoQH+sKAI4CABsACQrAHOsKAI4CABwAAwqKI7sMACoBAAAA.Gloreb:BAAANQAFFAQIBAAAAA==.',
Go='Goomi:BAAANQAECgEIAQAAAA==.Gordef:BAAANQAECgYIEwAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMIBgAAAA==.Grismago:BAAANQAECgEIAQAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgYIEAAAAA==.',
Ha='Haakon:BAAANQADCgUIBQAAAA==.Hanaya:BAAANQAECgEIAQAAAA==.Harrowing:BAABNQAECoEzAAIXAAkKyhp1HgDIAgAXAAkKyhp1HgDIAgAAAA==.Haurt:BAAANQAECgYIEgAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAAANQAECgYIEQAAAA==.',
Hi='Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAAANQAECgcICwAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAAANQADCgMIAwAAAA==.Hotmess:BAAANQAECgMIBQAAAA==.',
['Hô']='Hôly:BAAANQAECgcIDgAAAA==.',
In='Insanê:BAAANQAECggIBgABNQAECgkJIQAaAEgTAA==.Insañe:BAABNQAECoEhAAIaAAkKSBNjGwAKAgAaAAkKSBNjGwAKAgAAAA==.Invi:BAAANQAECgUJCAAAAA==.',
Ir='Ironbeef:BAAANQADCgcIBwAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICgAKAAAAAA==.Jadengras:BAAANQADCgYIDAAAAA==.Jasminetea:BAAANQADCgYIBgAAAA==.Jayylols:BAAANQAECgQJBAAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAAANQAECgYIEgAAAA==.',
['Jë']='Jësus:BAABNQAECoEZAAMdAAgKvBOgCACjAQABAAcKTxTLUwDNAQAdAAcK1RGgCACjAQAAAA==.',
Ka='Kalandaelis:BAAANQADCggJFQAAAA==.Kaldren:BAAANQADCgYIFAAAAA==.Kalel:BAAANQAECgQIBQAAAA==.Karmakazie:BAAANQAECgEIAQAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAAANQAECgUIDgAAAA==.Kazraghand:BAABNQAECoEZAAIFAAgK8QrMBQAAAgAFAAgK8QrMBQAAAgAAAA==.',
Ke='Keetanah:BAAANQADCgYIDAAAAA==.Kei:BAABNQAECoEhAAIMAAkK/BrnDgDaAgAMAAkK/BrnDgDaAgAAAA==.Kelsio:BAABNQAECoEcAAIDAAgKsBjMQgBZAgADAAgKsBjMQgBZAgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQAECgEJAQAAAA==.',
Kh='Kharos:BAABNQAECoEhAAIBAAkKGg0/QQAbAgABAAkKGg0/QQAbAgAAAA==.',
Ki='Kikeo:BAAANQAECgUIBQABNQAECgkJIQAMAPwaAA==.Kinks:BAAANQAECgQICgAAAA==.Kirkoth:BAAANQADCgcIEAAAAA==.',
Kn='Knuah:BAAANQADCgYIBgABNQAECgcIEgAKAAAAAA==.Knuts:BAAANQAECggIBwAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kovah:BAAANQAECggICgAAAA==.Kowtagion:BAABNQAECoEhAAMRAAkK6CUWBACdAwARAAkK6CUWBACdAwATAAEKeiUalgBoAAAAAA==.',
Kp='Kpopped:BAAANQADCgYJBgAAAA==.',
Kr='Krahz:BAAANQAECgUIBQAAAA==.Krelsh:BAABNQAECoEaAAQeAAgKbBuaJADhAQAeAAcKJxmaJADhAQADAAIKciAZ5gC7AAAFAAIK4gntDQBUAAABNQAECggIGgAZAE0WAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYICQAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kyruutos:BAAANQAECgMICQAAAA==.',
['Kí']='Kítkat:BAABNQAECoEUAAIfAAcKThVSVgC7AQAfAAcKThVSVgC7AQAAAA==.',
Le='Leibowitzy:BAABNQAECoEZAAMaAAcK0RQEJgCQAQAaAAcKVBEEJgCQAQAVAAUKIRIOFwAkAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAQAAAA==.Letra:BAAANQADCgMIAwAAAA==.Lexstrasza:BAAANQABCgIIAgAAAA==.',
Lh='Lhehitman:BAABNQAECoEZAAIYAAkKPB/AAQA/AwAYAAkKPB/AAQA/AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgEIAQAAAA==.Lightshax:BAAANQAECgcIEwAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAAANQAECgUIDQAAAA==.Liv:BAAANQADCgIIAgAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQADCgEIAQAAAA==.',
Lu='Luckydog:BAAANQADCggIFQAAAA==.Ludey:BAABNQAECoEjAAIgAAgKVRg8BABbAgAgAAgKVRg8BABbAgAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lumiya:BAAANQAECgEIAQAAAA==.Lutray:BAAANQAECgYIDwAAAA==.',
Ma='Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECoEkAAIBAAgK7g9USQD5AQABAAgK7g9USQD5AQAAAA==.Marodd:BAAANQAECgYIEwAAAA==.Mashîra:BAABNQAECoEcAAIDAAkK3SQHBACyAwADAAkK3SQHBACyAwAAAA==.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQADCggIGgAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECoEiAAMfAAkKVh3eGADeAgAfAAkKVh3eGADeAgAhAAEKwgc8KwA4AAAAAA==.Mekuro:BAAANQAECgIIAgAAAA==.Merihem:BAAANQADCgUICAAAAA==.Mewfasa:BAAANQADCggICAAAAA==.',
Mi='Mia:BAAANQAECgUIBQAAAA==.Milize:BAAANQAECgYIEwAAAA==.Minasuzune:BAAANQAECgYIEwAAAA==.Miney:BAAANQADCgUIBQAAAA==.Minus:BAAANQADCgIIAgAAAA==.',
Mo='Moondotter:BAAANQAECgMIAwAAAA==.Moongoddess:BAAANQAECgIJAgABNQAECgMIAwAKAAAAAA==.Moonslayer:BAAANQAECgYIDQAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.',
My='Mybanknoturs:BAAANQABCgQIBAAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAECgkJHAADAN0kAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAQABNQAECgkJHAADAN0kAA==.Måshîrå:BAAANQAECgYICAABNQAECgkJHAADAN0kAA==.',
Na='Nakor:BAAANQAECgQICwAAAA==.Nalian:BAAANQAECgYJDgAAAA==.Nalliella:BAAANQAECgUIDwAAAA==.Natashers:BAAANQADCgUIBQAAAA==.',
Ne='Neenzy:BAAANQAECgQIBwAAAA==.Nefeli:BAABNQAECoEaAAIcAAgKphNEBwDkAQAcAAgKphNEBwDkAQAAAA==.Nelinne:BAAANQAECgIIAwAAAA==.Nellevene:BAAANQAECgUICQAAAA==.Nestia:BAAANQAECgEIAQAAAA==.Never:BAABNQAECoEnAAMiAAkK4iEeIADRAgAiAAgKqyEeIADRAgAGAAUKqx2mGQCSAQAAAA==.',
Ni='Nightshade:BAABNQAECoEfAAIDAAgKphZBQgBbAgADAAgKphZBQgBbAgAAAA==.Nix:BAAANQADCgYIBgAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgYICgAAAA==.',
Oc='Ocllo:BAAANQAECgYIEwAAAA==.',
Og='Oghealz:BAAANQAECgQIBwAAAA==.',
Oj='Ojo:BAAANQAECgYIEQAAAA==.',
On='Oniana:BAABNQAECoEUAAIeAAUKTwkxQgDcAAAeAAUKTwkxQgDcAAAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAECggIGgAjAP0PAA==.',
Ow='Owwmyballs:BAAANQADCgMIAwAAAA==.',
Oz='Ozygo:BAAANQADCgcIDAAAAA==.',
Pa='Pagamas:BAABNQAECoEeAAMZAAkKIB0VSADPAgAZAAkKIB0VSADPAgAYAAIKixEcKABuAAAAAA==.Palandari:BAAANQAECgIJAgAAAA==.Pandawan:BAAANQAECgMIBQAAAA==.Panter:BAAANQAECgEIAQAAAA==.Paperplanes:BAAANQADCgQIBAAAAA==.',
Pe='Pebble:BAAANQAECgQICQAAAA==.',
Ph='Phodoe:BAAANQAECgYIEwAAAA==.',
Pi='Pinquisitor:BAAANQADCgQIAQABNQAECgMIBQAKAAAAAA==.',
Pl='Playne:BAAANQAECgQIBgAAAA==.',
Po='Pokeureyeout:BAAANQAECgIIBAAAAA==.Port:BAAANQAECgUIBgABNQAECgYIDgAKAAAAAA==.',
Pr='Prodyne:BAABNQAECoEjAAIZAAgKzhVwfgBHAgAZAAgKzhVwfgBHAgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECgUIBwAKAAAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAECgkJJQABAO8eAA==.Quiettreader:BAABNQAECoEZAAIYAAcK7hk1CAARAgAYAAcK7hk1CAARAgAAAA==.Quokka:BAAANQAECgMIBQAAAA==.',
Ra='Raegwin:BAAANQAECgQICAAAAA==.Raidboss:BAAANQAECgYIEAAAAA==.',
Re='Redeath:BAAANQAECgIJAgABNQAECgMIAwAKAAAAAA==.Redirect:BAAANQADCgcIHgABNQAECgMIAwAKAAAAAA==.Redonculous:BAAANQAECgcIEgAAAA==.Redpool:BAABNQAECoEiAAIfAAkKRg4vTwDWAQAfAAkKRg4vTwDWAQAAAA==.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECoEeAAIMAAYKgB59IAAOAgAMAAYKgB59IAAOAgAAAA==.Revansong:BAAANQADCgYICgABNQAECgcIGQAHAIIeAA==.Reymnant:BAAANQAECgIIAwAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.',
Ro='Ronx:BAAANQAECgQICAAAAA==.Roxxiloxxi:BAABNQAECoEZAAMGAAgKlQWuHgBoAQAGAAgKlQWuHgBoAQAiAAEKJwLKGwEgAAAAAA==.',
Ru='Rudeboy:BAABNQAECoEZAAIiAAgKEBcpSAA3AgAiAAgKEBcpSAA3AgAAAA==.Rushu:BAABNQAECoEaAAIZAAgKTRYPiAAxAgAZAAgKTRYPiAAxAgAAAA==.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECoEeAAMXAAgKng+LTADzAQAXAAgKng+LTADzAQAWAAcK1QynoABxAQAAAA==.Sagitta:BAAANQADCgcIBwABNQAECgYIEAAKAAAAAA==.Sahria:BAAANQAECgIIAgAAAA==.Sapphpal:BAAANQAECgYIBwAAAA==.Sarhia:BAAANQADCgUIBQAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgAKAAAAAA==.',
Sc='Schizology:BAAANQADCggIEAAAAA==.Schnoze:BAAANQAECgQICgAAAA==.',
Se='Sebekuul:BAAANQADCgYIBgAAAQ==.Selfie:BAAANQABCgIIAgAAAA==.Selys:BAABNQAECoElAAMZAAkKxRLAcwBhAgAZAAkKxRLAcwBhAgAYAAIK/QcwKgBkAAAAAA==.Sence:BAAANQABCgQIBAAAAA==.Sepheturix:BAAANQADCgQIBAAAAA==.Sephurik:BAACNQAFFIEPAAMZAAQKkhThGABMAQAZAAQKkhThGABMAQAYAAEKXQCTDQBHAAA1AAQKgTUAAxkACQpNIvcjADgDABkACQr5IPcjADgDABgAAQrvI4ooAGsAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowswife:BAAANQADCgYIBgAAAA==.Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQADCgQIBAAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawnalenee:BAAANQAECgIIAgABNQAECgQICQAKAAAAAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiriax:BAAANQAECgIJBAAAAA==.',
Si='Sikanda:BAAANQAECgcIBwAAAA==.Silvea:BAAANQAECgYICQAAAA==.Sinara:BAAANQAECgQIBQAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECoEfAAICAAgK6h4yDwDOAgACAAgK6h4yDwDOAgAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Sky:BAABNQAECoEYAAIZAAkKaiEgFQBvAwAZAAkKaiEgFQBvAwAAAA==.Skyelf:BAABNQAECoEeAAIDAAgKhwwkYQD/AQADAAgKhwwkYQD/AQAAAA==.',
Sl='Slimshadow:BAAANQABCgIJAgAAAA==.Sloppysloosh:BAAANQAECgYIDAAAAA==.',
Sm='Smallpox:BAAANQADCgUIDgAAAA==.Smokebreak:BAAANQADCggICAAAAA==.',
Sn='Snooflepoof:BAABNQAECoEiAAIfAAgK+xq/JACZAgAfAAgK+xq/JACZAgAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAYIFAAhANgeAA==.Solunara:BAAANQADCgUIBQABNQAECgUICAAKAAAAAA==.',
Sp='Spectrecles:BAABNQAECoEaAAIjAAgK/Q90OADcAQAjAAgK/Q90OADcAQAAAA==.Spectrecless:BAAANQADCgUIBQABNQAECggIGgAjAP0PAA==.Speez:BAAANQAECgUICgAAAA==.Sphester:BAAANQADCgUIBQAAAA==.',
St='Stablehand:BAAANQAECgQIBwAAAA==.Steve:BAACNQAFFIEOAAIkAAQK3QyTCgBPAQAkAAQK3QyTCgBPAQA1AAQKgS8AAyQACQoQIs0PAE8DACQACQoQIs0PAE8DAB8AAQo+Ao7yACkAAAAA.Stonedfel:BAABNQAECoEUAAILAAcKaQ/NNACkAQALAAcKaQ/NNACkAQAAAA==.',
Su='Sunhoof:BAAANQAECgUICAAAAA==.Supahotvile:BAAANQAECgQIBAAAAA==.',
Sy='Syx:BAAANQADCgYIBgAAAA==.',
['Sø']='Sørrow:BAAANQAECgUIDQAAAA==.',
Ta='Tabi:BAAANQAECgYIEwAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggJDQAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwAAAA==.',
Te='Test:BAAANQAECggJAQAAAA==.',
Th='Thedawg:BAAANQADCgEIAQAAAA==.Thedayman:BAAANQADCggICAAAAA==.Thetaint:BAABNQAECoEfAAIlAAkKrCFQBQBXAwAlAAkKrCFQBQBXAwAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAABNQAECoEbAAMDAAkK/yLrCwBdAwADAAkK/yLrCwBdAwAeAAEKQBkrYwBHAAAAAA==.',
To='Totemofpeace:BAAANQADCggICAABNQAECgcIBwAKAAAAAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Trentlock:BAABNQAECoEhAAMiAAkKzQ9LVwAEAgAiAAkKDw1LVwAEAgAGAAQKNhFnLwD3AAAAAA==.Tristae:BAAANQAECgUICQAAAA==.',
Ts='Tsu:BAAANQAECgYIBwAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unstablesha:BAAANQAECgEIAQAAAA==.',
Ut='Utilities:BAAANQADCggICAAAAA==.',
Va='Vaderbear:BAAANQADCggJCAAAAA==.Varandar:BAABNQAECoEjAAIRAAkKEiJDDQAnAwARAAkKEiJDDQAnAwAAAA==.',
Vi='Via:BAAANQADCgYICgAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vil:BAACNQAFFIEbAAICAAcKBSF2AADMAgACAAcKBSF2AADMAgA1AAQKgSEAAgIACQqvJmABAMgDAAIACQqvJmABAMgDAAAA.Vilonus:BAAANQAECgYIEQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwAAAA==.',
Vo='Voidbwoy:BAAANQADCggIEwAAAA==.Voy:BAAANQAECgYIEAAAAA==.',
Vu='Vulpes:BAAANQADCgYIBgAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
We='Weezy:BAAANQAECgYICgAAAA==.',
Wi='Williie:BAAANQAECgcICwAAAA==.Withengar:BAAANQADCggICAAAAA==.',
Wu='Wuoshi:BAAANQAECgIJBAABNQAECgMIAwAKAAAAAA==.Wuuzzyy:BAABNQAECoEcAAIjAAgKohHfMwD9AQAjAAgKohHfMwD9AQAAAA==.',
Xa='Xaliko:BAAANQAECgYJCQAAAA==.Xanbaran:BAABNQAECoEjAAIBAAgKAgpVXgCjAQABAAgKAgpVXgCjAQAAAA==.',
Xi='Xiphus:BAAANQABCgMIBQAAAA==.',
Xy='Xyrters:BAAANQADCgIIAgAAAA==.Xyrtrew:BAABNQAECoEoAAMfAAkK9CKCCgBMAwAfAAkK9CKCCgBMAwAkAAEKUByU6ABOAAAAAA==.',
Ya='Yahenni:BAAANQAECgYIEAABNQAECgcIBwAKAAAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yukki:BAAANQAECggIBgAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAAANQAECgcJDgAAAA==.',
Ze='Zerk:BAAANQAECggIDgAAAA==.',
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
