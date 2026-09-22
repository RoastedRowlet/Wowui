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

local lookup = {'Evoker-Preservation','Mage-Arcane','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Warlock-Demonology','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Shaman-Elemental','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Frost','Priest-Holy','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Druid-Feral','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Druid-Restoration','Shaman-Restoration','Mage-Frost','Paladin-Retribution','Shaman-Enhancement','Evoker-Augmentation','Monk-Mistweaver','Warrior-Arms','Monk-Windwalker','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abor:BAAANQAECgIIAgAAAA==.Abuela:BAAANQAECggIEQAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ae='Aegla:BAAANQAECgcIEQAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ak='Akiko:BAAANQAECgYICAAAAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAABNQAECoEjAAIBAAkK9BsvCADvAgABAAkK9BsvCADvAgAAAA==.Alerath:BAAANQADCgYIDAAAAA==.Alliar:BAAANQAECgcJEwAAAA==.Allynstraza:BAAANQAECgEIAgAAAA==.',
Am='Amgems:BAAANQAECgQIBQAAAA==.Amordred:BAAANQAECgIJAwAAAA==.',
An='Anasterion:BAAANQAECgcIEwAAAA==.Andarus:BAAANQAECgQIBAABNQAECgYIFwACABcSAA==.Ankles:BAABNQAECoEXAAMDAAgK5CG7DQAFAwADAAgK5CG7DQAFAwAEAAIKYAcNgwBeAAAAAA==.Ansley:BAAANQADCgUICAABNQAECgQIBgAFAAAAAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgEIAQABNQAECggJGAAGANMdAA==.',
As='Ashli:BAAANQAECgQIBgAAAA==.',
At='Atlasbär:BAAANQADCggJCAABNQADCgYIDwAFAAAAAA==.Atlasdark:BAAANQAECgUJBgABNQADCgYIDwAFAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.',
Ba='Balrock:BAAANQADCgcIBwAAAA==.Balthromaw:BAAANQAECgQJBwAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardwaffle:BAAANQAECgMIBAAAAA==.Bearlando:BAAANQAECgQJBAABNQAECgkJIQAHAPYfAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belstab:BAABNQAECoEhAAMIAAgKhAyAFgDzAQAIAAgKoguAFgDzAQAJAAcKggpTJQCuAQAAAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIEAAAAA==.',
Bg='Bgbalkoth:BAAANQADCgUIBwAAAA==.',
Bi='Bifurthegrey:BAAANQAECgMJAwAAAA==.Bigblammy:BAAANQADCggICAABNQAECgkJGAACACskAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Bloodavenger:BAABNQAECoEXAAIKAAkKZgxiOwAKAgAKAAkKZgxiOwAKAgAAAA==.Bloodemongar:BAAANQAECgcJDAAAAA==.Bloodhoundss:BAAANQAECgMJBAAAAA==.Blössöm:BAAANQAECgQICgAAAA==.',
Bo='Bobdk:BAACNQAFFIEKAAMEAAUKDxirAQDLAQAEAAUKDxirAQDLAQADAAEK1AliIQAlAAA1AAQKgSIAAgQACQqxIr0GAHcDAAQACQqxIr0GAHcDAAAA.Bomboklaat:BAAANQABCgYIBgAAAA==.Boomfrin:BAAANQADCgYJCwAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAAANQAECgcJEwAAAA==.',
Br='Braegen:BAAANQADCgYIDQABNQAECgYIFwACABcSAA==.Brewslee:BAAANQADCggICAAAAA==.Bruceleett:BAAANQAECgYJDgABNQADCgcIBwAFAAAAAA==.',
Bu='Buffmeister:BAAANQADCgUICQAAAA==.Bullioss:BAAANQABCgQIBgABNQAECgcIEAAFAAAAAA==.',
['Bè']='Bètrayèr:BAAANQABCgIIAgAAAA==.',
['Bö']='Böbbyboucher:BAAANQAECgUJCAAAAA==.',
Ca='Cainn:BAAANQADCggJEwABNQAECgYJEAAFAAAAAA==.Calfurion:BAAANQAECggIEQAAAA==.Capncrunch:BAAANQADCgUIBQAAAA==.Cazleah:BAABNQAECoEaAAILAAgKkBwkHgC9AgALAAgKkBwkHgC9AgAAAA==.',
Ce='Cessatio:BAAANQAECgQICgAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAAANQAECgUICgABNQAECgcIGQAIABESAA==.Chrisbrewn:BAAANQAECgYIEgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clevelandoe:BAABNQAECoEhAAMHAAkK9h/rCgD1AgAHAAkK9h/rCgD1AgAMAAMKLQz2xAC8AAAAAA==.',
Co='Cocobear:BAAANQADCgIIAgAAAA==.Coeurdeleon:BAAANQAECgcJDwAAAA==.Condemnation:BAAANQAECgcJEwAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgUIBQABNQADCggIDQAFAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQAFAAAAAA==.Coriantumr:BAAANQADCgYJBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQADCggJCAAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbazar:BAAANQABCgcJCwAAAA==.Curbstomped:BAAANQAECgYJDwAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgIIAgABNQAFFAUJDAANACoXAA==.Darkvizzy:BAABNQAECoEaAAQDAAcKfg9sSwBTAQADAAcKpwtsSwBTAQAEAAMKKRLabgCxAAAOAAIK3gpHWgB3AAAAAA==.Daymån:BAAANQAECgEJAQAAAA==.',
De='Deathreaper:BAAANQADCggJHgAAAA==.Delix:BAAANQAECgQJBQAAAA==.Demiplo:BAAANQAECgcIDQAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgMIBAAFAAAAAA==.Denelak:BAAANQAECgQIBQAAAA==.',
Di='Discipline:BAAANQAECgUJCwAAAA==.',
Do='Doggo:BAAANQADCgUICgAAAA==.',
Dr='Dratr:BAAANQAECgQJBgAAAA==.Draxyl:BAABNQAECoEbAAMDAAcKphJDOwClAQADAAcKphJDOwClAQAEAAcKQAPCVgAeAQAAAA==.Drekhan:BAAANQADCgMIAwABNQAECgYIFwACABcSAA==.Drham:BAAANQAECgcJEwAAAA==.Drokos:BAAANQABCgQIBwABNQAECgcIEAAFAAAAAA==.Drtree:BAAANQADCgcIBwAAAA==.',
Du='Dunhambones:BAAANQAECgYIDQAAAA==.Duo:BAAANQAECgUICwABNQAECgIIAgAFAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQADCgYIBgAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECoEcAAQPAAgKqw39SgCyAQAPAAgKqw39SgCyAQAQAAEK/gXnGwA3AAARAAEKxQAkZQARAAAAAA==.Elèctra:BAAANQAECgUIBAAAAA==.',
En='Enyô:BAAANQADCgQIBAABNQAECgUJCAAFAAAAAA==.',
Er='Erada:BAAANQAECgQIBgAAAA==.',
Ev='Evoklando:BAAANQADCgUICgABNQAECgkJIQAHAPYfAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgUIBwAAAA==.Expectpriest:BAAANQABCgQIBAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIAwABNQAECgIIAgAFAAAAAA==.',
Fe='Felad:BAAANQAECgQICgABNQAECgQICAAFAAAAAA==.',
Fh='Fhalanx:BAAANQABCggJCAAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECgEIAwABNQABCgQIBAAFAAAAAA==.Flappyy:BAAANQADCgQIBAAAAA==.Flowdinstuna:BAAANQAECgIIAwAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAAANQAECgYIEwAAAA==.Frierenpally:BAAANQADCgQJBAAAAA==.',
Fu='Furrybait:BAEANQAECgQIBAAAAA==.Furyiosa:BAAANQAECgcJDAAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgAFAAAAAA==.Gaiseric:BAABNQAECoEYAAIEAAgK6hXWKAAhAgAEAAgK6hXWKAAhAgAAAA==.Garrosh:BAAANQAECggJAQAAAA==.',
Ge='Geraniho:BAABNQAECoEbAAQGAAkKtR9WOQA4AgAGAAcK2BxWOQA4AgASAAQKCh8DIABMAQATAAEKtCRLHABJAAAAAA==.',
Gi='Girltank:BAAANQAECgIIAgAAAA==.',
Gn='Gnarlak:BAAANQABCgIIAgAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gotfleas:BAABNQAECoEVAAIUAAgKgCQ8AgBWAwAUAAgKgCQ8AgBWAwAAAA==.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAAANQAECgYJEQAAAA==.Greyfax:BAAANQAECggICAAAAA==.Grimthruul:BAAANQAECgYJDwAAAA==.Grommkar:BAAANQAECgcJDQAAAA==.',
Ha='Halucination:BAAANQAECgcJEQAAAA==.Harthan:BAAANQAECgEIAgAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayleigh:BAAANQADCgUIBQAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwAFAAAAAA==.Henchman:BAAANQABCgQICAABNQAECgcIEAAFAAAAAA==.Hetzák:BAAANQAECgYIEwAAAA==.',
Hi='Hintolisu:BAABNQAECoEYAAIVAAcKuxnvBwA1AgAVAAcKuxnvBwA1AgAAAA==.',
Ho='Hobbess:BAAANQAECgcIEAABNQAFFAcIEwAWAPQiAA==.Holybaloney:BAAANQAECgYJEAAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Hongis:BAAANQADCgUIBQAAAA==.Hoofinit:BAAANQAECgUICQAAAA==.',
Hu='Huatarm:BAAANQAECgYIEgAAAA==.',
Ia='Iadygaga:BAAANQAECgUIBQAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQADCgYIDQABNQAECgcIEQAFAAAAAA==.',
Ir='Ironspin:BAAANQAECgEIAQAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Ja='Jaark:BAABNQAECoEYAAIGAAkKCRw9EQAEAwAGAAkKCRw9EQAEAwAAAA==.Jabalru:BAAANQADCgMIAwAAAA==.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgEIAQABNQAECgQIBgAFAAAAAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jen:BAABNQAECoEZAAIPAAgKQhUSOwD/AQAPAAgKQhUSOwD/AQAAAA==.',
Jo='Jocon:BAAANQADCggIGwAAAA==.',
Ju='Jugulator:BAAANQADCgIIAgAAAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAAANQAECgcJDAABNQAECgUIBAAFAAAAAA==.Kanami:BAAANQAECgEIAgAAAA==.Kaynyx:BAABNQAECoEWAAIIAAcK9RkhEgAqAgAIAAcK9RkhEgAqAgAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAAANQAECgYJEAAAAA==.Kerb:BAAANQAECgEJAgAAAA==.Kery:BAAANQADCgMIAwAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECoEaAAMXAAgKmBrWFwBUAgAXAAgKkBfWFwBUAgAYAAQKzhYHPAAZAQAAAA==.',
Ki='Killinflak:BAAANQAECgIIAgAAAA==.Kissyboots:BAAANQAECgYJDgAAAA==.Kiyo:BAAANQAECgQICQABNQAECgcIEwAFAAAAAA==.',
Kn='Knewtoomuch:BAAANQADCgcJBwAAAA==.',
Ko='Konjur:BAABNQAECoEYAAICAAkKKySIGwBJAwACAAkKKySIGwBJAwAAAA==.',
Kr='Krelock:BAAANQAECgYJCgAAAA==.Krog:BAAANQADCgQIBAAAAA==.Krymzendeath:BAAANQAECgIIAgABNQAECggIGgAZANsUAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgUIBAAAAA==.',
['Kä']='Kämo:BAAANQAECgEIAQABNQAECgUIBAAFAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgQJBAABNQAECgkJIgAaADolAA==.Lakeyy:BAABNQAECoEiAAIaAAkKOiXuAAC8AwAaAAkKOiXuAAC8AwAAAA==.Lakeyys:BAAANQADCgcICQABNQAECgkJIgAaADolAA==.Lanuor:BAAANQADCgEIAQAAAA==.Lavagobrr:BAAANQAECgQIBAAAAA==.Lawrence:BAABNQAECoEaAAMbAAkKihpZJAB6AgAbAAkKihpZJAB6AgALAAMKiRgSmwDUAAAAAA==.',
Le='Lesaeria:BAAANQADCggICAAAAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQADCggICgAAAA==.Lightsardine:BAAANQADCgEJAQAAAA==.Lilikoii:BAAANQADCgMIBAABNQAECgkJIgAaADolAA==.Lilslaver:BAAANQAECgEJAQAAAA==.Lisex:BAACNQAFFIEHAAMOAAQKcAtsBgDnAAAOAAMKTwxsBgDnAAADAAEK0wgaIgAjAAA1AAQKgR8AAw4ACQpjIecHAC0DAA4ACQpjIecHAC0DAAMAAQoiFg6RAEQAAAAA.Lithe:BAAANQAECgcIEwAAAA==.',
Lo='Locklear:BAAANQAECgYIEAAAAA==.Logic:BAACNQAFFIELAAMCAAUKTBGlCwClAQACAAUKVBClCwClAQAcAAIK/hVcAgCrAAA1AAQKgSMAAgIACQqnIYksAAoDAAIACQqnIYksAAoDAAAA.',
Lu='Lunaria:BAAANQAECgEJAQABNQAECgkJIgAaADolAA==.Luxe:BAAANQAECgEIAQABNQAECgkJIgAaADolAA==.',
Ma='Macediin:BAAANQAECgQIBwAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECoEYAAIXAAkKVR06DgDSAgAXAAkKVR06DgDSAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgcJEwAFAAAAAA==.Magnolìa:BAAANQADCgcJDAAAAA==.Malthael:BAAANQAECgYJDAAAAA==.Mamageek:BAAANQAECgYJCgAAAA==.Mami:BAAANQAECgEJAQAAAA==.Manhorde:BAAANQAECgQJCAABNQAECgYICwAFAAAAAA==.Manix:BAAANQAECgIIBAAAAA==.Mareo:BAAANQADCgUIBQAAAA==.Marksterique:BAAANQAECgcJEwAAAA==.',
Me='Meeko:BAACNQAFFIELAAIBAAYK4RVyAgAPAgABAAYK4RVyAgAPAgA1AAQKgS0AAgEACQq3IYAEAEIDAAEACQq3IYAEAEIDAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgIJAgAAAA==.Metalbound:BAAANQAECgQICgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAAANQAECgcIEQAAAA==.Misslobster:BAAANQAECgQIBgAAAA==.',
Mo='Mokoko:BAABNQAECoElAAINAAkK0Rs+BwDZAgANAAkK0Rs+BwDZAgAAAA==.Mokolock:BAAANQAECgUJCAABNQAECgkJJQANANEbAA==.Moomoo:BAABNQAECoEXAAIWAAgKFhjCIQBfAgAWAAgKFhjCIQBfAgAAAA==.Moorlin:BAAANQADCggICAAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgkJJQANANEbAA==.',
My='Mysticphatty:BAAANQADCggJCAABNQAECgIIAgAFAAAAAA==.Myyst:BAAANQAECgIJAgAAAA==.',
Ne='Necro:BAAANQAECgcJEgAAAA==.Necrota:BAAANQAECgcJDgABNQAECgkJGAACACskAA==.Nekronomicon:BAAANQADCggICgABNQAECgcJEwAFAAAAAA==.Neuron:BAABNQAECoEaAAMaAAkKohhFCwC4AgAaAAkKohhFCwC4AgAWAAYKyhIsOgCfAQAAAA==.Nexborn:BAAANQABCggJCAAAAA==.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAAANQAECgYIEAAAAA==.Nightflame:BAAANQAECgQJCAAAAA==.Ninjavc:BAAANQAECgEJAQAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAAANQADCgQIBAAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQADCgIIAgAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgQICgAAAA==.Oreyn:BAAANQAECgQIBQAAAA==.',
Pa='Paladín:BAAANQAECgYIDQAAAA==.Palazar:BAABNQAECoEYAAIdAAcKcRy4RQA8AgAdAAcKcRy4RQA8AgAAAA==.Paoka:BAAANQADCgQIBwABNQADCgUICQAFAAAAAA==.Pargonz:BAABNQAECoEZAAMIAAcKERKLHQCmAQAIAAYKtROLHQCmAQAJAAIKlw72UAB/AAAAAA==.Patoko:BAABNQAECoEUAAIeAAcKghZlDQAkAgAeAAcKghZlDQAkAgAAAA==.Payn:BAAANQAECgQICAAAAA==.Paypay:BAABNQAECoEcAAIaAAgKVBkXEABoAgAaAAgKVBkXEABoAgAAAA==.',
Ph='Phalannx:BAAANQADCgIIAgAAAA==.Philipx:BAAANQAECgEIAQAAAA==.',
Pi='Piglittle:BAAANQAECgEJAQAAAA==.Pindad:BAAANQAECgcICgABNQAECgcIEAAFAAAAAA==.',
Pl='Plzdispelme:BAAANQAECgYICQAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAAANQAECgUJCgAAAA==.',
Pr='Proshvam:BAAANQAECgEIAQAAAA==.',
Ra='Ragingmonkx:BAAANQAECgYIEAAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Raventer:BAAANQAECgYIBgAAAA==.Razlock:BAAANQADCgIJAgAAAA==.Razorclaws:BAAANQADCggJFQAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAAANQAECgUIDQAAAA==.',
Ro='Rollos:BAAANQAECgUIEAAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAAANQAECgMJBAAAAA==.Ryujinsimp:BAACNQAFFIEMAAMNAAUKKhfXAQCzAQANAAUKKhfXAQCzAQAfAAQKYhVVAgBMAQA1AAQKgSIAAx8ACQoJJQ0CABcDAA0ACQruIiwEADQDAB8ACAqEJA0CABcDAAAA.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMJAwAFAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQADCgUIBQABNQAFFAIIAwAFAAAAAA==.Saintnick:BAAANQAECgIJAgAAAA==.Samtarkras:BAAANQAECgcJEgAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAACNQAFFIEJAAQTAAUKhg7UAQCfAAATAAIKCg7UAQCfAAAGAAIKLhSpFwCeAAASAAEKLwT6EwBPAAA1AAQKgYcABBMACQpOIosBAPMCAAYACArhIGgOABkDABMABwqAJIsBAPMCABIABQrmIhQNAAcCAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAECgkJIQAHAPYfAA==.Shangzha:BAAANQAECgYIDwAAAA==.Shareholder:BAEANQAECgQIBAABNQAECgkJIAACACUlAA==.Shiivera:BAAANQAECgYJEQAAAA==.Shimada:BAABNQAECoEXAAIMAAgKyBx/IQC1AgAMAAgKyBx/IQC1AgAAAA==.Shotsyll:BAAANQAECgYJCQAAAA==.',
Sk='Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAAANQAECgcICgAAAA==.Skynomad:BAAANQAECgUICwAAAA==.',
Sl='Slyde:BAAANQAECgYIDAAAAA==.',
Sm='Smalldk:BAAANQAFFAEJAQABNQAFFAMJCAAdAOALAA==.Smallrichard:BAAANQADCgYJBgABNQAECgUIBwAFAAAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAAANQAECgQIBgAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgUIDgAFAAAAAA==.',
Sn='Snek:BAAANQAECgEIAgAAAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Solborne:BAAANQABCgIIAgAAAA==.Solfreid:BAAANQAECgMIBAABNQAECgUIBQAFAAAAAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwADAHkmAA==.Soulfang:BAAANQAECgQJCAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAAANQADCgUIBQABNQAECggJEwAFAAAAAA==.Sprocketrot:BAAANQADCgIIAgAAAA==.',
Sq='Squidmonk:BAABNQAECoEYAAIgAAkKqA14EAD2AQAgAAkKqA14EAD2AQAAAA==.',
St='Stardrive:BAABNQAECoEdAAIhAAkKFw7eUQAlAgAhAAkKFw7eUQAlAgAAAA==.Steelwhacka:BAAANQAECgUICwAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAABNQAECoEbAAIiAAkK8R1+DQClAgAiAAkK8R1+DQClAgAAAA==.Stormstyle:BAAANQAECgQJCAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAAANQAECgUIBwAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQADCgcIBwABNQAECgUICwAFAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgQICgAAAA==.Surtur:BAABNQAECoEbAAIhAAgKrRklQQBiAgAhAAgKrRklQQBiAgAAAA==.Sus:BAAANQAECgYIBwAAAA==.',
Sy='Sygismund:BAAANQAECgEJAQAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAABNQAECoEUAAIMAAcKQhouQwAsAgAMAAcKQhouQwAsAgAAAA==.Taotien:BAAANQAECgUJBQAAAA==.',
Tc='Tchaik:BAAANQAECgYIEwAAAA==.',
Te='Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgQIBQAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQADCggICAAAAA==.Thickthang:BAABNQAECoEhAAMeAAgKeCWNAgBfAwAeAAgKeCWNAgBfAwALAAQKAhX7kgDpAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECoEcAAIjAAgKLB/hAgDTAgAjAAgKLB/hAgDTAgAAAA==.Tinytea:BAABNQAECoEcAAMiAAgKFhz6DwB6AgAiAAgKZRv6DwB6AgAkAAEKUB7pHwBWAAAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgIJAgAAAA==.Tolivan:BAAANQAECgYIDwAAAA==.Tonali:BAAANQAECgYIDQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgUICAAFAAAAAA==.',
Tr='Trusinner:BAABNQAECoEbAAIhAAgK/BpfNwCJAgAhAAgK/BpfNwCJAgAAAA==.',
Ts='Tsusha:BAEANQAECgQJBgAAAA==.',
Tu='Turkeyleg:BAAANQADCggJHwAAAA==.',
Tw='Twippy:BAABNQAECoEeAAILAAkKsBXUKAB2AgALAAkKsBXUKAB2AgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgcIEgABNQAECgMJAwAFAAAAAA==.Tyriam:BAAANQAECgYIEwAAAA==.',
Va='Valess:BAAANQAECgEIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYJBgAAAA==.Veronique:BAABNQAECoEiAAINAAkKgx+oBAAlAwANAAkKgx+oBAAlAwAAAA==.Verso:BAAANQAECgQIBQAAAA==.',
Vi='Viberaider:BAAANQAECgYIBgAAAA==.Vitalithry:BAAANQAECgUJCgAAAA==.Vivii:BAAANQAECgYJCgAAAA==.Vizzysmash:BAAANQADCggICAABNQAECgcIGgADAH4PAA==.',
Vo='Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.',
Wa='Warchicken:BAAANQAECgUJBwAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECoEaAAMOAAgK5hGtIQDqAQAOAAgK+BCtIQDqAQADAAUK+gsmZADfAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAAANQAECgYICwAAAA==.',
Wi='Wiiska:BAABNQAECoEiAAMRAAkKrx2PDwCmAgARAAgKsxyPDwCmAgAPAAIKSAIWoQBUAAAAAA==.Windoelicker:BAAANQADCgcIBwAAAA==.',
Wo='Worgya:BAAANQADCgUIBQABNQAECgUIBAAFAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgcIEAAFAAAAAA==.Wrlccywhefr:BAABNQAECoEeAAQJAAkK6iHiEQB2AgAJAAcKkx7iEQB2AgAlAAYKkx3IBgATAgAIAAIKZB0eNACrAAAAAA==.',
Wu='Wuggles:BAABNQAECoEbAAIaAAkKhhQ6DwB2AgAaAAkKhhQ6DwB2AgAAAA==.',
Xa='Xalatoes:BAAANQADCggJGwAAAA==.',
Xb='Xbalanque:BAAANQAECgQIDAAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwAhAPwaAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQAECgEIAQAAAA==.',
Ye='Yetil:BAAANQAECgQIBgAAAA==.',
Yn='Ynotraw:BAABNQAECoEZAAIhAAkK9xnzLAC3AgAhAAkK9xnzLAC3AgAAAA==.',
Yo='Yourephired:BAAANQAECgQICAAAAA==.',
Za='Zaycursed:BAAANQAECgQICgABNQAECggJGwALAAUfAA==.Zaydream:BAAANQADCgcIBwABNQAECggJGwALAAUfAA==.Zaylight:BAAANQADCggICAABNQAECggJGwALAAUfAA==.Zayseer:BAABNQAECoEbAAILAAgKBR/BGgDXAgALAAgKBR/BGgDXAgAAAA==.',
Ze='Zello:BAAANQAECgQJBgAAAA==.',
Zh='Zhengy:BAAANQADCgUICAABNQAECgYIFwACABcSAA==.',
Zi='Ziggybeast:BAAANQAECggIEwAAAA==.Zignag:BAAANQADCgYIBgAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgQIBQAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggJGwALAAUfAA==.',
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
