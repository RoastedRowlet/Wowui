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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Druid-Balance','Evoker-Devastation','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Shaman-Restoration','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Subtlety','Paladin-Retribution','Rogue-Assassination','Priest-Holy','Mage-Fire','Mage-Arcane','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Paladin-Holy','Paladin-Protection','Hunter-Survival','Shaman-Enhancement','Druid-Restoration','Druid-Feral','Druid-Guardian','Monk-Brewmaster','Warrior-Protection','Mage-Frost',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aadrisedh:BAAANQADCgMIAwAAAA==.Aaeryn:BAAANQADCgMIAwAAAA==.Aaliyshaa:BAAANQAECgIIBAAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAAANQAECgcIEgAAAA==.',
Ab='Abrakadabruh:BAAANQAECgMIAwAAAA==.Abyssal:BAAANQAECgQICAAAAA==.',
Ac='Achin:BAAANQADCgQIBAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICQAAAA==.',
Ai='Aidoffhealer:BAAANQADCgQIBQAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCgUICAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQADCgYIDgAAAA==.Alystair:BAAANQADCgYIBgABNQAECgIJAgABAAAAAA==.',
Am='Amadayus:BAABNQAECoEVAAICAAgKJyRAEQA2AwACAAgKJyRAEQA2AwAAAA==.Ambellina:BAAANQADCggIHAAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAABNQAECoE1AAQDAAgKVRwWCgCFAQAEAAcKyhqfTgAhAgADAAUKZhkWCgCFAQAFAAEKyRmoYQBIAAAAAA==.Arclock:BAAANQAECgQICAAAAA==.Arconnai:BAABNQAECoErAAIGAAkK1h/3IwADAwAGAAkK1h/3IwADAwAAAA==.Areiotyrict:BAAANQADCgQIBAAAAA==.Arnøld:BAAANQAECgIIAgAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.',
As='Asham:BAAANQADCgYIEAAAAA==.Asiago:BAAANQAECgQICgABNQAECgcIGQAHAM0eAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgIJAgAAAA==.',
Av='Avvalethra:BAAANQAECgYIEwAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCAABNQAFFAYIDwAIAPcYAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAAANQAECgMIBAAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECoEcAAIJAAcKZxVtTwDqAQAJAAcKZxVtTwDqAQAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgYJDAAAAA==.',
Be='Bearlinwall:BAAANQADCggIHQAAAA==.Bearmaster:BAAANQAECgIIBAAAAA==.Belacc:BAAANQADCggIDgAAAA==.Belfiyajr:BAAANQAECgcICgAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAAANQAFFAEIAQAAAA==.Billybones:BAAANQAECgMICAAAAA==.Bimbobaby:BAAANQABCgEIAQAAAA==.',
Bl='Blackholes:BAAANQAECgQICQAAAA==.Blackwÿn:BAAANQADCggIEwABNQAECgUIDQABAAAAAA==.Bladeblade:BAAANQAECgUIBgABNQAECgkJJwAGALwgAA==.Bladedozzer:BAAANQAECgIIBAAAAA==.Blindinglite:BAABNQAECoEYAAIKAAcKHhnwJQAdAgAKAAcKHhnwJQAdAgAAAA==.Bloodhaze:BAABNQAECoEXAAIKAAkKOyLbEADkAgAKAAkKOyLbEADkAgAAAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQADCggIHgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombalatty:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.',
Br='Brchm:BAAANQAECgQIBQAAAA==.Brickly:BAABNQAECoEZAAMKAAkKsR0wEgDWAgAKAAgKNx4wEgDWAgALAAEKfRknIgBLAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgcIGQAHAM0eAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQADCggIHQAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.',
Bx='Bxxberry:BAAANQADCggIIwAAAA==.',
['Bú']='Búkki:BAAANQADCgYIFgAAAA==.',
['Bü']='Bükkï:BAAANQADCgcIDAAAAA==.',
Ca='Caboodles:BAAANQAECgUICwAAAA==.Camishami:BAAANQAECgcICAAAAA==.Candyhandz:BAAANQADCgUICQABNQAECgIIAwABAAAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.',
Ce='Ceraph:BAAANQADCgQIBAAAAA==.Cexiback:BAABNQAECoElAAIMAAkKLR0ZCgAdAwAMAAkKLR0ZCgAdAwAAAA==.Cexifist:BAAANQAECgEIAQAAAA==.',
Ch='Cheebsz:BAAANQADCgYICwAAAA==.Cheesus:BAABNQAECoEZAAIHAAcKzR4qJwBeAgAHAAcKzR4qJwBeAgAAAA==.Chicharon:BAAANQAECgUIDQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAAANQAECgQICQAAAA==.Chunggus:BAAANQABCgYIBgAAAA==.Churva:BAABNQAECoEUAAMJAAcKJAiSmgAMAQAJAAYKOwSSmgAMAQANAAYKZAbungDhAAAAAA==.',
Co='Coko:BAAANQADCgYIBgABNQAECggIHgACAP8aAA==.Condemned:BAAANQADCgQIBgAAAA==.Coochie:BAAANQAECgIIAgAAAA==.Cosecantes:BAAANQAECgQIDgAAAA==.Cowdozer:BAAANQADCggICwAAAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgQIBAAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAAANQAECgQIDgAAAA==.Critsandgigg:BAAANQADCgIIAgAAAA==.Crusäderaura:BAAANQAECgQIBwAAAA==.Cryptìc:BAACNQAFFIEGAAIOAAQKORINBwBKAQAOAAQKORINBwBKAQA1AAQKgR8AAg4ACQqqIAwKABwDAA4ACQqqIAwKABwDAAE1AAQKBwgQAAEAAAAA.Cryptîc:BAAANQAECgcIEAAAAA==.',
Da='Dabbia:BAABNQAECoEdAAQDAAkKeR3YBgDxAQADAAYKRR/YBgDxAQAEAAQK0xyvlQBLAQAFAAQKMxdpKwANAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Damented:BAAANQADCggIEQABNQAECgkJIwANABIZAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQADCgUIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIAgAAAA==.',
De='Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAABNQAECoEaAAMPAAgKCBEmLADZAQAPAAgKCBEmLADZAQAQAAIKWwcjnwBVAAAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAAANQADCgQIBQAAAA==.Delthrus:BAAANQAECgQIBwABNQAECgYIEgABAAAAAA==.Demonarc:BAABNQAECoEYAAIMAAkKvBNLGABoAgAMAAkKvBNLGABoAgAAAA==.Detreset:BAAANQAFFAEIAQAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAAANQAECgYIDgAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECggIHAARADQkAA==.Disorder:BAAANQAECgEIAQAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECggIHAARADQkAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgABAAAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQADCgIIAgAAAA==.Dragtiago:BAAANQADCgEIAQAAAA==.Drakarys:BAAANQADCgIIAgAAAA==.Drexybear:BAAANQAECgYIDQAAAA==.Drezbi:BAAANQAECgEIAQAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECoEcAAISAAcKNAn6pQBkAQASAAcKNAn6pQBkAQAAAA==.Durzaka:BAAANQAECgEIAQAAAA==.Durzu:BAAANQAECgQIDgAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECoEhAAMTAAkKkg0+IAAkAgATAAkKVQ0+IAAkAgARAAYKJAlzKgA7AQAAAA==.',
Eg='Eggy:BAAANQAECggIBgAAAA==.Egholom:BAABNQAECoEeAAIKAAcKVghVRgAgAQAKAAcKVghVRgAgAQAAAA==.',
El='Electrcfrost:BAABNQAECoEdAAIJAAkKFBj7JwCnAgAJAAkKFBj7JwCnAgAAAA==.Elkanàh:BAAANQAECgcIDQABNQAFFAQICQAUAPMSAA==.Elorene:BAABNQAECoEdAAMVAAgKLAi/AgC1AQAVAAgKCQi/AgC1AQAWAAYK9gEYTQG7AAAAAA==.Elunara:BAAANQAECgYIDgABNQAECggINQADAFUcAA==.Elyysian:BAACNQAFFIEKAAIOAAUKkRSzBACjAQAOAAUKkRSzBACjAQA1AAQKgSMAAw4ACQrpHtgIAC8DAA4ACQrpHtgIAC8DABQAAwqWA2myAIAAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIAwAAAA==.',
Er='Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgIJAgABAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAABNQAECoEeAAIWAAkKmCCQLwASAwAWAAkKmCCQLwASAwAAAA==.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.',
Ew='Ewoo:BAAANQAECgYICwABNQAECgcIEwABAAAAAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.',
Fa='Fadam:BAAANQAECgYIDAAAAA==.Faei:BAAANQADCgUICAAAAA==.Famjam:BAAANQAECggIAgAAAA==.Fatigue:BAAANQADCgcIBwAAAA==.Fatpo:BAABNQAECoEXAAQUAAgK2hytSgDzAQAUAAcK3xutSgDzAQAOAAQKuB9lLQBoAQAXAAEKBSBvGwBXAAABNQAECgkJGQAKALEdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECoEhAAIWAAkK6hpNTgC+AgAWAAkK6hpNTgC+AgAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAABNQAFFIEFAAIJAAIK/wWPGwCLAAAJAAIK/wWPGwCLAAAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgkJJgAWAG4eAA==.Fourpriest:BAAANQADCggIFQAAAA==.Foô:BAABNQAECoEcAAMTAAgK0BviEgCeAgATAAgK0BviEgCeAgARAAUKAhO2KgA5AQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgEIAgAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.Furyrosa:BAAANQADCgcIBwAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Fy='Fyah:BAAANQAECgcIEwABNQAFFAUICgACANUOAA==.Fyaza:BAAANQADCggICAABNQAFFAUICgACANUOAA==.',
Ga='Gaga:BAAANQADCgIIAgAAAA==.Gargamels:BAAANQAECgUIBQAAAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggICgAAAA==.Gerttie:BAAANQAECgcIEAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFIETAAIYAAYKPBKPBADmAQAYAAYKPBKPBADmAQA1AAQKgR4AAhgACQqeHu4LAMACABgACQqeHu4LAMACAAAA.',
Go='Gobsquadp:BAAANQAECgQICQABNQAECgcIEwABAAAAAA==.',
Gr='Grassmoker:BAAANQAECgMIAwAAAA==.Grek:BAAANQAECgcIDQABNQAECgkJHQAZABUeAA==.Grievex:BAABNQAECoEZAAISAAgKqgXZqgBYAQASAAgKqgXZqgBYAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIGwAAAA==.Grozloo:BAAANQADCgMIAwAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAECgkKHQAaAEQcAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAABNQAECoEcAAIUAAgK5BxXJAChAgAUAAgK5BxXJAChAgAAAA==.Heelz:BAAANQADCgMIBAAAAA==.Hemostasis:BAABNQAECoErAAQSAAkKHSO4DACCAwASAAkKHSO4DACCAwAbAAEKghjX4wBKAAAcAAEKHRaeUgBAAAAAAA==.Herjä:BAAANQAECgQIDAAAAA==.Hexem:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Hexoon:BAAANQAECgQIBAAAAA==.',
Ho='Homeslice:BAAANQAECgUIDgAAAA==.',
Hu='Huntweak:BAAANQADCggICQAAAA==.Huun:BAABNQAECoEdAAIdAAgKnx6MAgDZAgAdAAgKnx6MAgDZAgAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQADCgcJBwAAAA==.',
Ia='Iamgabrielsj:BAABNQAECoEfAAMEAAYKdAfirAASAQAEAAYKLAbirAASAQAFAAMKBAYISwCIAAAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
Ir='Irrenadro:BAABNQAECoElAAISAAgKyQy+jQCgAQASAAgKyQy+jQCgAQAAAA==.',
Is='Islandhunter:BAAANQABCgQJBAAAAA==.',
Iy='Iyahna:BAAANQAECgQIBgAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgUICgAAAA==.',
Je='Jeage:BAAANQAECgMIBAAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgQIBQABNQAECggIFwAeAMwhAA==.',
Jo='Joes:BAAANQAECgYIDwAAAA==.Jonesy:BAAANQAECgEIAQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCgcIDgAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAcIFAASAAkXAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAECggINQADAFUcAA==.',
Ke='Keetra:BAABNQAFFIEGAAICAAQKmQtJCgA2AQACAAQKmQtJCgA2AQAAAA==.Keiriline:BAAANQAECgUICAAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.',
Kl='Klix:BAAANQADCgQJBAABNQAECgIIAwABAAAAAA==.',
Kn='Knight:BAABNQAECoEWAAMWAAkKFRp8WgCfAgAWAAgKdBt8WgCfAgAVAAIK9QtPBwBwAAAAAA==.Knuggz:BAAANQAECgMIBAAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ku='Kubluk:BAAANQAECgIIAgAAAA==.Kumbustinher:BAAANQADCgYIBwAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAECgkJJgAUAGomAA==.Kylepala:BAAANQAECgYIBgABNQAECgkJJgAUAGomAA==.Kylepriest:BAABNQAECoEmAAMUAAkKaia6AADfAwAUAAkKaia6AADfAwAXAAIKKSPIEgDAAAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Lambeáu:BAAANQAECgIIAgAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAAANQAECgIIAQAAAA==.Lamdadk:BAAANQADCggICQAAAA==.Landistis:BAAANQADCgYICwAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDgAAAA==.Larzoe:BAAANQADCgUIBQABNQAECggIHAAKAKwfAA==.Larzoh:BAABNQAECoEcAAMKAAgKrB9OEwDKAgAKAAgKrB9OEwDKAgAMAAMKug/CSACnAAAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lemonheads:BAAANQAECgUICwAAAA==.Lethargy:BAAANQADCgUICQAAAA==.Levapally:BAAANQADCgUICAAAAA==.',
Li='Lidorila:BAAANQADCgMICAAAAA==.Lightguard:BAABNQAECoEVAAISAAcKmxfCcADwAQASAAcKmxfCcADwAQAAAA==.Lilplottwist:BAAANQAECgYIDgAAAA==.Lilwiz:BAAANQADCgcIEgAAAA==.Linalala:BAABNQAECoEzAAMfAAgK2CVWAwB6AwAfAAgK2CVWAwB6AwAgAAEK0AeALgAxAAAAAA==.Linnxvx:BAAANQADCgYIBgAAAA==.Lishp:BAAANQADCgYIBgAAAA==.Literacola:BAAANQAECgQIBgAAAA==.',
Lo='Lorino:BAAANQADCgUIBQAAAA==.Lothaire:BAAANQABCgIIAgAAAA==.',
Lu='Lubaduba:BAAANQADCggIDQAAAA==.Lugeya:BAAANQADCgcICwAAAA==.Lugeyamnk:BAAANQADCgEIAQAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lustnbeiber:BAABNQAECoEXAAQJAAcKGhdTRgAPAgAJAAcKGhdTRgAPAgANAAQKMQlFugCiAAAeAAEKgwLWKwA1AAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgYICAAAAA==.',
Ly='Lyncha:BAAANQADCgIIAgABNQAECgYIDwABAAAAAA==.Lynchà:BAAANQAECgYIDwAAAA==.',
Ma='Maakun:BAABNQAECoEaAAIUAAgKKxZ0OQA9AgAUAAgKKxZ0OQA9AgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Magawarrior:BAAANQADCgQIBAAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAABNQAECoEiAAMNAAkK1x75EgAFAwANAAkK1x75EgAFAwAJAAQKvBcklQAYAQAAAA==.Malfrun:BAAANQAECgYIEgAAAA==.Marinnite:BAAANQADCgYIBgAAAA==.Marox:BAABNQAECoEZAAIWAAcKDRpZkQAbAgAWAAcKDRpZkQAbAgAAAA==.Marrøwgar:BAAANQADCggIIQAAAA==.Mathrim:BAABNQAECoElAAMEAAkK6yTyAgC0AwAEAAkK6yTyAgC0AwAFAAIKjhWGSgCKAAAAAA==.Matooka:BAAANQAECgUICQAAAA==.Maynji:BAAANQADCggICAAAAA==.',
Mc='Mcthugger:BAAANQADCgYIEAABNQAECggIGAASADsXAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYJEgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAAANQAECgQIBgAAAA==.Mommÿ:BAABNQAECoEjAAMUAAkKQhZwLAB3AgAUAAkKQhZwLAB3AgAXAAYKSAzGDAA1AQAAAA==.Moneymage:BAAANQAECgQIBAAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECoElAAIhAAkK3xKLDgD8AQAhAAkK3xKLDgD8AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECggIHgACAP8aAA==.Moolificent:BAAANQAECgUICAAAAA==.Moonshea:BAAANQADCgQIBAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAAANQAECgcIEQAAAA==.',
Mu='Muddbane:BAAANQADCgQIBAABNQAECgcIHQATAHEWAA==.Muddgore:BAAANQADCggIDgABNQAECgcIHQATAHEWAA==.Muddthir:BAAANQADCgQIBAABNQAECgcIHQATAHEWAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgQIBAABNQAECggIJgACAJsiAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECoEdAAMTAAcKcRaBKADiAQATAAcKBBOBKADiAQARAAQKPRUsLwAKAQAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Nestaah:BAAANQADCgYJCwAAAA==.Nethender:BAAANQADCgMIAwAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.',
Ni='Nirath:BAABNQAECoEaAAIWAAcKMwlM0gCQAQAWAAcKMwlM0gCQAQAAAA==.Nisia:BAAANQAECgQIBAABNQAECgkJJwAGALwgAA==.Nito:BAABNQAECoEhAAIPAAkKeRLSIgAiAgAPAAkKeRLSIgAiAgAAAA==.',
No='Nohkano:BAABNQAECoEkAAIiAAkKnSWJAADeAwAiAAkKnSWJAADeAwAAAA==.Nokt:BAAANQAECgIJAgAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECgYIDQAAAA==.Noveerra:BAAANQADCgIIAgAAAA==.',
Nu='Numbuh:BAAANQAECgQIBgAAAA==.Nusix:BAAANQADCggIEAAAAA==.',
Oa='Oakrogue:BAAANQADCggIHwAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Ov='Overdoze:BAAANQADCgUICwAAAA==.',
Pa='Painwhisper:BAAANQABCgQJBAAAAA==.Paladeez:BAAANQAECgYICwABNQAECgkJKwASAB0jAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcJDAAAAA==.Pantheons:BAAANQADCgYIBwAAAA==.Parsi:BAABNQAECoEWAAILAAYKvho0CgDaAQALAAYKvho0CgDaAQAAAA==.Pattysmyth:BAAANQADCggIGAABNQADCggIDgABAAAAAA==.Paulinemaroi:BAAANQAECgcICgAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECgcICgABAAAAAA==.Pawtism:BAAANQAECggICAAAAA==.',
Pe='Peleaihonua:BAAANQADCgQJBQABNQAECgIIAwABAAAAAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Philip:BAAANQAECgUIBwAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQAKALEdAA==.Polis:BAAANQADCgcIBwABNQAECgQJDAABAAAAAA==.Pottyy:BAAANQABCgIIAgAAAA==.Pougadina:BAAANQAECgIIAgABNQAECgkJGQAKALEdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcJBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgQIBQABNQAECgYIDgABAAAAAA==.',
['Pä']='Pändora:BAAANQADCggIDgAAAA==.',
Ra='Rabite:BAAANQAECgcIEwAAAA==.Radiance:BAEANQAECgIIAgABNQAFFAMIBQAaABIfAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQADCgYJCQAAAA==.Ramshunter:BAAANQAECgMIBQAAAA==.Randyvivaldi:BAAANQAECgEIAwAAAA==.Rashanda:BAAANQAECgQIBAAAAA==.Rathasas:BAAANQAECgUIEQAAAA==.Ratnob:BAAANQAECgcIDwAAAA==.',
Re='Reddemon:BAABNQAECoEdAAMZAAkKFR6YAgACAwAZAAkKFR6YAgACAwAIAAEKfwZ8NQAvAAAAAA==.Relda:BAAANQAECgIIAwABNQAECggIFwAeAMwhAA==.Remye:BAABNQAECoEaAAIbAAgKDhQDRQAQAgAbAAgKDhQDRQAQAgAAAA==.Rennshi:BAABNQAECoEdAAIKAAkK0SV5AwCsAwAKAAkK0SV5AwCsAwAAAA==.Reportedhunt:BAAANQAECgYIEgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Richie:BAAANQADCgcJBwAAAA==.',
Ro='Rolanthas:BAAANQAECgQIEAAAAA==.Roldaza:BAAANQAECgEIAQAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECoEmAAMCAAgKmyIAGAALAwACAAgKmyIAGAALAwAaAAQKLAZ6TwCXAAAAAA==.',
Ru='Rulep:BAAANQADCgEIAQAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Rythmatic:BAABNQAECoEcAAMRAAgKNCTmCADTAgARAAcKOyTmCADTAgATAAYKESFPHQA9AgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQADCggIEwABNQADCgEIAQABAAAAAA==.Sakieri:BAABNQAECoEZAAMOAAgKSxcAGQBCAgAOAAgKSxcAGQBCAgAUAAEKKQNazAArAAAAAA==.Salazar:BAAANQAECgEJAQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQADCgYIDAAAAA==.Sangan:BAABNQAECoEdAAIWAAgK5ho0XACbAgAWAAgK5ho0XACbAgAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwABAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Selaris:BAAANQADCggICAAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFIEPAAIIAAYK9xiCAQD8AQAIAAYK9xiCAQD8AQA1AAQKgSEAAggACQqUIr0DAEsDAAgACQqUIr0DAEsDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQAECgEJAQAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQADCgQIBAAAAA==.Sharpshotz:BAAANQADCgcIBwAAAA==.Shenanigan:BAAANQAECgUJBQAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECoEUAAMEAAgK2RyuQgBKAgAEAAcKVR2uQgBKAgAFAAIKhhoESACSAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAAANQAECgYIEwAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJHQAZABUeAA==.Smilingp:BAAANQADCgUIBQAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgUJBwAAAA==.Sourmash:BAAANQADCgYIBwAAAA==.',
St='Starfrost:BAAANQADCgIJAwAAAA==.Stingerai:BAABNQAECoEeAAICAAgK/xqVLACpAgACAAgK/xqVLACpAgAAAA==.Stingerjb:BAAANQAECgIIAgABNQAECggIHgACAP8aAA==.',
Su='Subjugator:BAAANQAECgMIAwAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwAAAA==.',
Sy='Syl:BAAANQAECgIIAwAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECggIEwABAAAAAA==.Teemonk:BAAANQAECggIEwAAAA==.Teepal:BAAANQADCgUIBQABNQAECggIEwABAAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAAANQAECgIIBAAAAA==.Teribullduce:BAABNQAECoEaAAICAAcKgSP5MwCNAgACAAcKgSP5MwCNAgAAAA==.Terscheckii:BAAANQADCgYIDAAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thingol:BAAANQABCgYIEQAAAA==.Thormor:BAAANQAECgQICAABNQAFFAYIEwAYADwSAA==.Thugger:BAAANQADCgYICQABNQAECggIGAASADsXAA==.Thuggerjr:BAABNQAECoEYAAISAAgKOxerXQApAgASAAgKOxerXQApAgAAAA==.Thundersurge:BAAANQADCggIHAAAAA==.Thænes:BAAANQAECgUIDQAAAA==.Thûr:BAAANQADCgYIDAABNQAECgkJIwANABIZAA==.',
Ti='Tigg:BAAANQAECggIDgAAAA==.Tinkerdinker:BAAANQADCgUIBQAAAA==.Tipsout:BAABNQAECoEnAAMGAAkKvCAYFQBMAwAGAAkKvCAYFQBMAwAjAAYK3xJ8GABJAQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECggIEwABAAAAAA==.Totemm:BAAANQAECgcICgAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECoEjAAMNAAkKEhnUKgB5AgANAAkKEhnUKgB5AgAJAAQK2wqDsQDZAAAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassidas:BAAANQADCgYIBgAAAA==.Trealin:BAAANQADCgYICAAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFAAAAA==.Tyrsside:BAAANQAECgQIBQAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIAwAAAA==.',
Un='Unfocused:BAABNQAECoEjAAIHAAkKnBjhGwC6AgAHAAkKnBjhGwC6AgAAAA==.',
Ur='Urgmathron:BAAANQAECgQICAAAAA==.',
Va='Vakhara:BAAANQAECgIIAwAAAA==.Valorisa:BAAANQAECgMIAwABNQAFFAUICgAOAJEUAA==.Vansthir:BAAANQAECggIBgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaush:BAAANQADCggIIgAAAA==.',
Ve='Veigär:BAAANQAECgEIAQAAAA==.Verasuchi:BAAANQADCgYIBgAAAA==.',
Vi='Vinsmoke:BAAANQADCggIDwAAAA==.',
Vo='Voidflare:BAAANQAECgQICQAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Volcanoez:BAAANQADCgYIBwAAAA==.Vonrx:BAAANQAECgEIAwAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECggIGgAHAIIiAA==.',
Wa='Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAAAAA==.',
We='Welfairline:BAAANQADCggIFwAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAECgcIGgACAIEjAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAAANQAECgcIDAAAAA==.Yassera:BAAANQAECgQJDAAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAAANQAECgUICwAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgUIEQAAAA==.Zarik:BAAANQAECgIIAwAAAA==.',
Ze='Zeddoc:BAEANQADCgYIFwAAAA==.Zedward:BAEANQADCgMIBQABNQADCgYIFwABAAAAAA==.Zenfist:BAAANQADCgQIBAAAAA==.Zenoath:BAAANQAECgQIBQAAAA==.',
Zo='Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQADCgYICgAAAA==.',
Zu='Zulugangrene:BAABNQAECoEYAAISAAcKkwxHmwB+AQASAAcKkwxHmwB+AQAAAA==.Zun:BAABNQAECoEVAAIkAAYKqgmHEgA9AQAkAAYKqgmHEgA9AQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgUIDQABAAAAAA==.',
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
