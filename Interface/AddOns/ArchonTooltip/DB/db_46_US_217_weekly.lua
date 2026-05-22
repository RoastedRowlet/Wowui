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

local lookup = {'Mage-Fire','Monk-Windwalker','Shaman-Restoration','Priest-Holy','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Shaman-Elemental','Warrior-Protection','Shaman-Enhancement','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Druid-Guardian','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','Unknown-Unknown','DemonHunter-Devourer','Priest-Shadow','DemonHunter-Vengeance','Warlock-Demonology','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','Paladin-Protection','Warlock-Destruction','DeathKnight-Blood','Druid-Restoration','Druid-Feral','Monk-Brewmaster','Warlock-Affliction','Evoker-Augmentation','Monk-Mistweaver','Rogue-Subtlety',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Abanados:BAABLgAECn8VAAIBAAcJKg7WBABAAQABAAcJKg7WBABAAQAAAA==.',
Ak='Akatsuki:BAABLgAECn84AAICAAkJYCQ9AgAnAwACAAkJYCQ9AgAnAwAAAA==.Aken:BAAALgADCgYJBgAAAA==.',
Al='Alight:BAAALgAECgMJAwABLgAECggJGgADAFQeAA==.Althea:BAABLgAECn8kAAIEAAgJMxG8KACrAQAEAAgJMxG8KACrAQAAAA==.',
Am='Ambition:BAAALgAECgEJAQABLgAFFAQJCwAFABAVAA==.Amoredis:BAAALgADCggJDgAAAA==.',
An='Animorpha:BAAALgAECgMJAwAAAA==.',
Ar='Ariane:BAAALgAECgIJAgAAAA==.Arkaen:BAABLgAECn8mAAIGAAgJMyBLHADAAgAGAAgJMyBLHADAAgAAAA==.Arkhyn:BAAALgAECgUJCAAAAA==.',
As='Ashengor:BAAALgAECgMJBAAAAA==.Asonda:BAEBLgAECn8fAAMEAAgJoBVmHACmAQAEAAcJphZmHACmAQAHAAYJFQjpLwAOAQAAAA==.Assi:BAAALgADCgEJAQAAAA==.',
Az='Azshauyssa:BAAALgAECgcJEQAAAA==.',
Ba='Baelsk:BAAALgADCgYJBgAAAA==.Bajamama:BAABLgAECn8hAAMIAAgJghQeIQCTAQAIAAgJghQeIQCTAQADAAYJ/g7zTABPAQAAAA==.Batou:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgADCgUJBQAAAA==.Bel:BAAALgAFFAEJAQABLgAECgkJNwAJANwiAA==.Betarius:BAAALgAECgUJBQABLgAECggJGgADAFQeAA==.Betiff:BAABLgAECn8aAAMDAAgJVB6gGwAlAgADAAcJSx2gGwAlAgAIAAcJ7BDiSQAgAQAAAA==.',
Bi='Birddog:BAAALgAECgkJCQAAAA==.',
Bl='Blazeschill:BAAALgADCgEJAQABLgAECgkJOwAKAOoYAA==.Blooded:BAABLgAECn8XAAILAAkJgQ2FCQCBAQALAAkJgQ2FCQCBAQAAAA==.Bloodydraco:BAABLgAECn81AAMMAAkJhhlRBQCJAgAMAAkJhhlRBQCJAgANAAEJpwWOHwAuAAAAAA==.Bloodymagus:BAAALgADCgkJCQAAAA==.',
Bo='Bolden:BAAALgADCgkJHQAAAA==.',
Br='Brelm:BAAALgADCgQJBwAAAA==.Brewzin:BAAALgADCgQJBAAAAA==.Bruwu:BAAALgAECgYJCQAAAA==.',
Bu='Bubblez:BAAALgADCgQJBAAAAA==.',
Ca='Cakebro:BAABLgAECn86AAIOAAkJQSF0BQCiAgAOAAkJQSF0BQCiAgAAAA==.Camembert:BAABLgAECn8qAAIPAAkJ7yLIAQD4AgAPAAkJ7yLIAQD4AgAAAA==.Casii:BAAALgAECggJEQAAAA==.',
Ce='Cele:BAAALgAECgMJBAAAAA==.Celyne:BAAALgAECgEJAQAAAA==.',
Ch='Chiizo:BAABLgAECn8UAAIHAAYJsRLWJwBXAQAHAAYJsRLWJwBXAQAAAA==.Chiror:BAAALgADCgYJCQAAAA==.Chubingus:BAABLgAECn8eAAIQAAkJfyBMFACXAgAQAAkJfyBMFACXAgAAAA==.Chuckmcstabb:BAAALgAECgEJAQAAAA==.Chufeng:BAABLgAECn8UAAIRAAcJUB7uIwAOAgARAAcJUB7uIwAOAgABLgAFFAMJBwAFAL8hAA==.',
Co='Coggette:BAABLgAECn8UAAISAAYJxgR8/gD+AAASAAYJxgR8/gD+AAAAAA==.Corvica:BAAALgADCgEJAQAAAA==.',
Cr='Crizadin:BAAALgAECgMJAwAAAA==.Crizuid:BAAALgAECgUJCQABLgAECgcJEwATAAAAAA==.Crocubot:BAAALgAECgIJBQAAAA==.',
Cu='Cucuyknight:BAAALgADCgEJAgAAAA==.',
Da='Danaki:BAAALgAECgYJEAAAAA==.Dancookerton:BAAALgADCgUJBQAAAA==.Danorace:BAAALgAECgQJBQAAAA==.Darkcurve:BAAALgAECgYJCgAAAA==.Darkhope:BAAALgAECgYJCgAAAA==.',
De='Deija:BAABLgAECn8bAAIUAAgJfh5NJAADAgAUAAgJfh5NJAADAgAAAA==.Dekoo:BAABLgAECn8rAAIJAAcJmiNDBwBVAgAJAAcJmiNDBwBVAgAAAA==.Demon:BAAALgAECgcJEwAAAA==.Demoneyez:BAAALgAECgYJCQAAAA==.Deusene:BAABLgAECn8YAAIVAAYJHhCzLgBsAQAVAAYJHhCzLgBsAQAAAA==.',
Dr='Drakula:BAAALgAECgcJDwAAAA==.Dreadfang:BAABLgAECn88AAIQAAkJcCPtCgDmAgAQAAkJcCPtCgDmAgAAAA==.Droka:BAABLgAECn8sAAIDAAgJdR+fDACzAgADAAgJdR+fDACzAgAAAA==.',
El='Elavil:BAAALgADCgYJEAAAAA==.Eldrynath:BAAALgAECgMJAwAAAA==.',
En='Endel:BAAALgADCgcJCwAAAA==.',
Eu='Eurotophobia:BAABLgAECn8bAAIGAAcJbxUbXwB2AQAGAAcJbxUbXwB2AQAAAA==.',
Ex='Exodia:BAABLgAECn8dAAMRAAgJnhjUNQDAAQARAAcJoRnUNQDAAQAOAAMJJw4dJACrAAAAAA==.',
Fa='Faldrithor:BAAALgAECgMJAwAAAA==.',
Fe='Fellaria:BAABLgAECn8oAAMWAAkJ4yN2AQDeAgAWAAkJ4yN2AQDeAgAUAAEJmA2M4QArAAAAAA==.',
Fh='Fhyllo:BAAALgAECggJEwAAAA==.',
Fl='Fluffybella:BAAALgAFFAIJBAAAAA==.',
Fo='Follaglas:BAABLgAECn8hAAIRAAgJ0iTPBwDpAgARAAgJ0iTPBwDpAgAAAA==.',
Ga='Gairen:BAAALgAECgcJDgAAAA==.Galadisis:BAABLgAECn88AAMFAAkJpyFdBQDZAgAFAAkJpyFdBQDZAgAJAAIJ/BgpLgCOAAAAAA==.Galtidor:BAAALgAECgIJAgAAAA==.',
Gh='Ghuldana:BAABLgAECn8iAAIXAAgJ7B5dGwBOAgAXAAgJ7B5dGwBOAgABLgAECgYJEAATAAAAAA==.',
Gl='Glowgasm:BAAALgADCgMJAgAAAA==.',
Go='Goji:BAAALgADCgMJAwAAAA==.Goon:BAAALgAECgMJBAAAAA==.Goonann:BAAALgAECgkJEwAAAA==.',
Gr='Grimfoul:BAAALgADCgEJAQAAAA==.Gryari:BAAALgAECgcJDAAAAA==.',
Gu='Guiche:BAAALgAECgYJCQAAAA==.',
Gw='Gwiynevere:BAABLgAECn8XAAIQAAYJdwUEsgDSAAAQAAYJdwUEsgDSAAAAAA==.',
He='Heathclif:BAAALgADCgUJCgABLgAFFAMJBwAFAL8hAA==.Hellao:BAABLgAECn8zAAIYAAgJaRpqEQALAgAYAAgJaRpqEQALAgAAAA==.Hellmage:BAAALgADCgcJEQAAAA==.Hermano:BAAALgADCgUJBQAAAA==.',
Ho='Hoxpox:BAAALgAECgQJBAAAAA==.',
Hr='Hrimceald:BAAALgAECgYJCgAAAA==.',
Hy='Hylts:BAABLgAECn8gAAIKAAYJchbXEwASAQAKAAYJchbXEwASAQAAAA==.',
Id='Idpswhileafk:BAAALgADCgEJAQAAAA==.',
Il='Illithian:BAAALgAECgUJBQAAAA==.',
Im='Imalockyo:BAAALgAECggJCgAAAA==.',
Ja='Javi:BAAALgADCgkJCQABLgAECgkJKAAWAOMjAA==.',
Je='Jedus:BAAALgAECgEJAQABLgAECgcJKwAJAJojAA==.',
Ji='Jizzmon:BAAALgAECgEJAQAAAA==.',
Ka='Kaidirra:BAAALgADCgYJBgAAAA==.Kassiandra:BAABLgAECn8sAAMGAAgJTBhyQwC/AQAGAAgJTBhyQwC/AQAZAAYJ5gciWQAXAQAAAA==.Katja:BAAALgAECgYJBwABLgAECggJGwAUAH4eAA==.',
Ke='Keeyla:BAAALgADCgcJCgAAAA==.Kejiabaobei:BAABLgAECn8qAAIRAAkJkiWIAwBZAwARAAkJkiWIAwBZAwAAAA==.Kesta:BAAALgAECgQJBgAAAA==.Kevsterr:BAAALgAECgUJBQAAAA==.',
Kh='Khaantu:BAAALgADCgEJAQAAAA==.',
Ki='Kirin:BAAALgADCgYJCQAAAA==.',
Ko='Koi:BAAALgAECgIJBQABLgADCgEJAQATAAAAAA==.Korah:BAAALgADCgcJCwAAAA==.',
Kp='Kpöp:BAABLgAECn8lAAMUAAgJoyJnGgA+AgAUAAgJoyJnGgA+AgAaAAIJ2wrnaABBAAAAAA==.',
Kr='Krakens:BAEALgAECgUJBwABLgAECggJHwAEAKAVAA==.Krayel:BAAALgAECgIJAgAAAA==.Krîtz:BAAALgADCgcJBAAAAA==.Krünk:BAABLgAECn8zAAIMAAkJIyDVAQA9AwAMAAkJIyDVAQA9AwAAAA==.',
Kt='Kt:BAAALgAFFAEJAgAAAA==.',
Ku='Kumquat:BAAALgADCgEJAQAAAA==.Kuubai:BAAALgADCggJCAAAAA==.',
La='Lachdanan:BAABLgAECn8dAAIbAAgJQw54FQAwAQAbAAgJQw54FQAwAQAAAA==.Lament:BAABLgAECn8nAAIUAAgJSyLRDgCVAgAUAAgJSyLRDgCVAgAAAA==.Lans:BAAALgADCgEJAQAAAA==.',
Le='Leafbeard:BAAALgAECgYJBgAAAA==.',
Li='Lilean:BAABLgAECn8UAAIRAAgJwh4nEwCeAgARAAgJwh4nEwCeAgAAAA==.',
Lo='Lokka:BAABLgAECn8fAAMKAAgJTBmkCgC3AQAKAAgJTBmkCgC3AQADAAYJgRX2VAAJAQAAAA==.Lolly:BAAALgAECgQJBAAAAA==.Loralin:BAAALgADCgcJDQAAAA==.',
Ly='Lyreshade:BAABLgAECn8nAAIIAAkJDxI6JQDnAQAIAAkJDxI6JQDnAQAAAA==.Lyreshaded:BAAALgAECgkJEAABLgAECgkJJwAIAA8SAA==.',
Ma='Maatdemon:BAAALgADCgcJCgABLgAECgkJOAACAGAkAA==.Madbunny:BAAALgADCgUJBwAAAA==.Madriina:BAAALgADCgYJDAAAAA==.Mahrah:BAABLgAECn8fAAIPAAgJoRM2EACFAQAPAAgJoRM2EACFAQAAAA==.Manashifter:BAAALgAECgYJDgAAAA==.Mar:BAAALgADCgcJBwAAAA==.Marija:BAAALgAECgQJCAABLgAECggJGwAUAH4eAA==.',
Me='Melevolence:BAABLgAECn88AAMXAAkJkR03EgCNAgAXAAkJkR03EgCNAgAcAAMJ9wZjQQCvAAAAAA==.Mep:BAAALgAECgUJBwABLgAECgUJBwATAAAAAA==.Meplastered:BAAALgAECgYJEwAAAA==.',
Mi='Mirithari:BAAALgADCgkJCQAAAA==.',
Mo='Molby:BAAALgAFFAEJAQABLgAFFAMJBAATAAAAAA==.Monkehh:BAAALgAECgUJCAABLgAECgcJCQATAAAAAA==.Moolinda:BAABLgAECn8eAAIDAAgJNhcWJwDZAQADAAgJNhcWJwDZAQAAAA==.Morticia:BAABLgAECn8aAAQdAAgJixz3DwAMAgAdAAgJixz3DwAMAgAQAAUJNwrQuwDCAAALAAEJEgtxJAAyAAAAAA==.Motgul:BAAALgAECgUJBwAAAA==.',
My='Mythbras:BAAALgAECgUJCgAAAA==.Mythfurry:BAAALgAFFAIJAwABLgAFFAUJGQAeAFsKAA==.',
Na='Naxria:BAAALgAECgcJDgAAAA==.',
Ne='Nezanu:BAABLgAECn8bAAIfAAgJQSC6AwCOAgAfAAgJQSC6AwCOAgAAAA==.',
Ni='Nic:BAAALgADCgUJBQAAAA==.Niiko:BAAALgADCgEJAQAAAA==.Nimithriel:BAABLgAECn8lAAIVAAkJGBQ1GADAAQAVAAkJGBQ1GADAAQAAAA==.',
No='Notwesa:BAAALgAECgEJAQAAAA==.Notweso:BAABLgAECn8uAAIUAAkJHyJLCgDGAgAUAAkJHyJLCgDGAgAAAA==.',
Oc='Oconostota:BAAALgAECgEJAQAAAA==.',
Ol='Oliverclutch:BAAALgADCgIJAgAAAA==.',
Or='Oriari:BAAALgADCgQJBAABLgAECgYJDwATAAAAAA==.Oroki:BAAALgAECgEJAQAAAA==.',
Pa='Paarthurnax:BAAALgAECgYJBgAAAA==.Pallywack:BAAALgADCgcJBwAAAA==.Parizade:BAAALgAECgMJAwAAAA==.Pat:BAAALgAECgMJAwAAAA==.',
Pe='Pergi:BAAALgADCgkJDwABLgAECggJIQARANIkAA==.',
Pi='Pithikos:BAAALgAECgUJCQABLgAFFAMJBwAFAL8hAA==.',
Po='Pocketrapper:BAAALgAECgUJBQAAAA==.Poovey:BAACLgAFFH8LAAIFAAQJEBWIEwA2AQAFAAQJEBWIEwA2AQAuAAQKfyQAAgUACQmSHa8RACkCAAUACQmSHa8RACkCAAAA.',
Pu='Purpletoe:BAABLgAECn8ZAAMEAAkJkhy0BgDNAgAEAAkJkhy0BgDNAgAVAAYJihLKKwAuAQAAAA==.',
Py='Pyronae:BAABLgAECn8sAAIXAAgJJxThOQC/AQAXAAgJJxThOQC/AQAAAA==.',
Qi='Qit:BAAALgAECgEJAQABLgAECgcJCwATAAAAAA==.',
Ra='Radrek:BAAALgADCggJCAAAAA==.Rargh:BAABLgAECn8gAAIRAAkJzw8/QgCUAQARAAkJzw8/QgCUAQAAAA==.',
Re='Redonkeylous:BAAALgAECgMJAwAAAA==.Rengen:BAABLgAECn8UAAMgAAgJ7g47KwArAQAgAAcJtQ47KwArAQACAAEJSBCxcQA2AAAAAA==.Restobear:BAAALgAECgEJAQAAAA==.Reya:BAABLgAECn8fAAMQAAgJyx0RNgDuAQAQAAgJGxwRNgDuAQAdAAYJHxrCFwBaAQAAAA==.',
Ri='Rixadin:BAAALgADCgEJAQAAAA==.',
Ru='Runelord:BAAALgAECgYJCwAAAA==.',
Sa='Saeli:BAABLgAECn8xAAIYAAkJthWiFwDGAQAYAAkJthWiFwDGAQAAAA==.Saeris:BAAALgAECgUJBQAAAA==.Sakagawea:BAAALgADCgMJAwAAAA==.Sanamongolos:BAAALgAECgIJAgAAAA==.Sasinko:BAABLgAECn8sAAIhAAgJGB6FAwAkAgAhAAgJGB6FAwAkAgAAAA==.Sasqüatch:BAAALgADCgQJBAAAAA==.Satjin:BAAALgAECgYJEgAAAA==.Sawlrenuk:BAAALgADCgEJAQAAAA==.',
Sc='Scamander:BAABLgAECn8VAAIiAAcJmRyiGADRAQAiAAcJmRyiGADRAQAAAA==.',
Se='Sentien:BAAALgAECgcJAQAAAA==.',
Sh='Shadowstripe:BAABLgAECn8iAAQCAAgJbBD0IgBSAQACAAcJ8xH0IgBSAQAjAAMJ8QPyZQA6AAAgAAEJGAaIjAAsAAAAAA==.Shambamtymam:BAAALgADCgMJAwAAAA==.Shaylathia:BAAALgAECgEJAQAAAA==.Shigglez:BAACLgAFFH8GAAISAAMJrRBcWwDxAAASAAMJrRBcWwDxAAAuAAQKfzAAAhIACAk+IvMXAJcCABIACAk+IvMXAJcCAAAA.Shiitake:BAAALgAECgMJAwAAAA==.',
So='Sonatina:BAACLgAFFH8bAAMHAAgJ8SH/AQC6AgAHAAgJNR7/AQC6AgAEAAQJPSTyBACsAQAuAAQKfyQAAwcACAmxJR0DAD4DAAcACAmxJR0DAD4DABUABwmuHzoXAMkBAAAA.Soulfly:BAABLgAECn85AAMCAAgJRBprFgC8AQACAAgJRBprFgC8AQAgAAUJjAY5UACRAAAAAA==.',
St='Steamedhams:BAAALgAECgYJBgAAAA==.Streat:BAAALgADCgMJAwAAAA==.Streatlight:BAAALgADCgcJDQAAAA==.',
Su='Sugarpants:BAABLgAECn85AAIjAAgJ5xiuEgAsAgAjAAgJ5xiuEgAsAgAAAA==.Sulfuric:BAAALgAECgEJAQAAAA==.Sumtongue:BAAALgAECgYJDwAAAA==.',
Sy='Sylphrenä:BAABLgAECn8gAAMjAAgJ+B2RGQDvAQAjAAcJQB2RGQDvAQACAAYJ+xRvKQAqAQAAAA==.',
Ta='Tark:BAAALgAECgYJDQABLgAECgYJDQATAAAAAA==.',
Te='Tembtree:BAABLgAECn8ZAAMYAAYJ2hMGLwAXAQAYAAYJ2hMGLwAXAQAeAAEJoQLRzgAcAAABLgAECggJKQAcAFkRAA==.Temlock:BAABLgAECn8pAAMcAAgJWRHKCQBhAQAcAAgJWRHKCQBhAQAXAAMJ8AEY+wBkAAAAAA==.',
Th='Thrawnn:BAACLgAFFH8HAAIFAAMJvyH8GQAVAQAFAAMJvyH8GQAVAQAuAAQKfy8AAgUACQlRJYACACMDAAUACQlRJYACACMDAAAA.',
Tr='Tryamarula:BAAALgADCgEJAQAAAA==.Trysomecider:BAAALgADCgIJAwAAAA==.',
Tu='Tuonetar:BAAALgAECgMJAwAAAA==.Turan:BAAALgAECgYJDQAAAA==.',
Ty='Tyrenari:BAAALgAECgQJCQAAAA==.',
Ul='Ultear:BAABLgAECn8YAAQWAAYJHRg3DwASAQAUAAYJDg/MZQBwAQAWAAYJqBc3DwASAQAaAAIJ/xBtXABuAAAAAA==.',
Ve='Velkyn:BAACLgAFFH8HAAIkAAMJTwtAHADeAAAkAAMJTwtAHADeAAAuAAQKfzQAAiQACQlsGCcLAC4CACQACQlsGCcLAC4CAAAA.Vetenarae:BAAALgADCgMJAwABLgAECgYJIAAKAHIWAA==.',
Vo='Volkren:BAABLgAECn85AAIdAAgJBiG9BgB3AgAdAAgJBiG9BgB3AgAAAA==.',
Wa='Warhunter:BAAALgAECgQJBAAAAA==.',
Xa='Xandor:BAAALgADCgYJBgABLgAECgYJCgATAAAAAA==.Xaos:BAAALgAECgYJCwAAAA==.',
Xi='Xiaowugui:BAAALgADCgUJBQAAAA==.',
Xz='Xzaroth:BAAALgADCgcJBwAAAA==.',
Ya='Yarrick:BAABLgAECn88AAIDAAkJkh/4BgAAAwADAAkJkh/4BgAAAwAAAA==.',
Yo='Yonst:BAABLgAFFH8GAAIEAAMJxwweFwC5AAAEAAMJxwweFwC5AAAAAA==.',
Yu='Yumemi:BAAALgADCgcJAgAAAA==.',
Ze='Zelkiri:BAAALgAECgYJDgAAAA==.Zeref:BAAALgAECgQJBAABLgAECgkJOAACAGAkAA==.Zerotwoo:BAAALgADCgYJBgAAAA==.Zethlahr:BAABLgAECn82AAMVAAkJhR1ZCACPAgAVAAkJhR1ZCACPAgAEAAQJpA2tUgDtAAAAAA==.',
Zo='Zoros:BAAALgAECgYJCgAAAA==.',
Zy='Zytheri:BAAALgADCgEJAQAAAA==.',
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
