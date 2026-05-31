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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Elemental','Hunter-Survival','Rogue-Subtlety','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation','Druid-Feral','DemonHunter-Vengeance','Warrior-Arms','Druid-Guardian','Paladin-Protection','Priest-Discipline','Warrior-Fury',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAYJEQABAF0iAA==.',
Ab='Abadizzo:BAAALgAECgcJBwAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyEVEQCzAgACAAkJtyEVEQCzAgAAAA==.Abilities:BAAALgAECgYJEgAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAAALgAECgYJEgABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgIJAwAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airleara:BAAALgAECgcJDAAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RTgJgDMAAABAAMJ3RTgJgDMAAAuAAQKfzEAAgEACQnEHoEKAJcCAAEACQnEHoEKAJcCAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.Aite:BAAALgAECgIJAgAAAA==.',
Al='Alexian:BAABLgAECn8aAAIGAAgJHhSZBwCuAQAGAAgJHhSZBwCuAQAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAAALgAECgcJEgAAAA==.',
Am='Amebeliever:BAABLgAECn8fAAQHAAgJiB8ZFQBDAgAHAAcJuB4ZFQBDAgAIAAcJAgi/NwAMAQAJAAQJ/gmCXwCAAAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ar='Arahgon:BAEBLgAECn8UAAIKAAcJLRQqmAApAQAKAAcJLRQqmAApAQABLgAECgUJBgAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAQJCQADADEdAA==.Asukà:BAABLgAECn80AAMLAAgJnBZaJQAUAgALAAgJnBZaJQAUAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgADCgEJAQABLgAECgYJFQAMANIPAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAAALgAECgcJEwABLgAFFAMJCAAOAJkRAA==.Bellarg:BAABLgAECn82AAMPAAgJphgpPADdAQAPAAgJphgpPADdAQAQAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAAALgAECgcJEwAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAMJAwAAAA==.Bigfaust:BAABLgAECn8YAAQJAAcJqB8ZKQBYAQAJAAUJpx8ZKQBYAQAIAAUJABu/LgBDAQAHAAIJRR8IUwDFAAAAAA==.',
Bl='Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAABLgAECn8UAAIKAAgJCgi1ngAeAQAKAAgJCgi1ngAeAQAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAABLgAECn8WAAMIAAcJpRrsFgAKAgAIAAcJpRrsFgAKAgAHAAQJBiMjMAAvAQABLgAFFAcJEwAEAKcYAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAFAAAAAA==.Broo:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEQAAAA==.Calculusx:BAABLgAECn8tAAIRAAkJUCP1AAAPAwARAAkJUCP1AAAPAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8gAAMSAAYJ+RtBBAAtAgASAAYJrhtBBAAtAgATAAIJmRtuAgCcAAAuAAQKfzcABBIACQkrJgsFALEDABIACQn7JQsFALEDABQACQnjIeECAAUCABMAAwnIInUKAL0AAAAA.',
Ch='Champu:BAAALgADCgEJAQAAAA==.Chaoticx:BAAALgADCgQJBQAAAA==.Charlotte:BAAALgAECgcJEwAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn83AAIJAAkJ6yAzBAD3AgAJAAkJ6yAzBAD3AgABLgAFFAMJCAAOAJkRAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECgcJDgAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn83AAIVAAkJYxJ9FADKAQAVAAkJYxJ9FADKAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMJAAYJ2Rs0LwCaAQAJAAUJGhw0LwCaAQAHAAYJsRShNwBAAQAAAA==.Darilol:BAAALgAECgUJBQABLgAECgYJFQAMANIPAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn8qAAIWAAcJECM8DAAvAgAWAAcJECM8DAAvAgAAAA==.Debra:BAACLgAFFH8GAAIVAAMJlAsAFgC/AAAVAAMJlAsAFgC/AAAuAAQKfy0AAhUACQnCG2kNAC8CABUACQnCG2kNAC8CAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8dAAMXAAcJbSIhCwCeAgAXAAcJbSIhCwCeAgAYAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAgAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJAwAAAA==.Demize:BAAALgAECgYJBwAAAA==.Demonflame:BAABLgAECn8nAAIQAAkJDxanBQD3AQAQAAkJDxanBQD3AQAAAA==.Demíze:BAAALgAECgEJAQAAAA==.Deshield:BAAALgAECgcJBwABLgAFFAQJGgALACYmAA==.Deus:BAABLgAECn8bAAISAAkJexCdZwCUAQASAAkJexCdZwCUAQAAAA==.Dewry:BAAALgAECgYJEwAAAA==.',
Dh='Dhudamuthi:BAACLgAFFH8FAAIJAAMJmBneNwCxAAAJAAMJmBneNwCxAAAuAAQKfzsAAgkACQmfJDsCADEDAAkACQmfJDsCADEDAAAA.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJAQAAAA==.',
Do='Donnajuan:BAABLgAECn86AAMNAAkJShxqCQDhAgANAAkJShxqCQDhAgAKAAEJ2QMIoAEbAAAAAA==.Dornath:BAABLgAECn81AAIKAAgJwQ+8dQBoAQAKAAgJwQ+8dQBoAQAAAA==.',
Dr='Draaxelro:BAABLgAECn8bAAICAAkJ9RAjTQCiAQACAAkJ9RAjTQCiAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAQJGgALACYmAA==.Dragontiddys:BAABLgAECn8fAAMZAAgJRx/HBADEAgAZAAgJRx/HBADEAgAaAAEJJBbAfABCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Drim:BAAALgADCgkJDAAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAIYAAkJxwqeJgB3AQAYAAkJxwqeJgB3AQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAcJIwAbAHsNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8IAAICAAMJExO5TwDhAAACAAMJExO5TwDhAAAuAAQKfzEAAgIACQkAH8QOAMUCAAIACQkAH8QOAMUCAAAA.',
Em='Embertal:BAAALgAECgYJEAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMcAAYJNxZEOQBrAQAcAAYJNxZEOQBrAQALAAUJthG1dwDVAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAgABLgAECgkJGgAVAJ4iAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8pAAIKAAgJ8gfinQAfAQAKAAgJ8gfinQAfAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8PAAIOAAYJyyFRBADmAQAOAAYJyyFRBADmAQAuAAQKfxgAAg4ACQlrI1cLACICAA4ACQlrI1cLACICAAEuAAUUBwkWAAkAmyEA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Finke:BAABLgAECn8bAAISAAcJZhzrZwAHAgASAAcJZhzrZwAHAgAAAA==.Fishmärket:BAABLgAECn8iAAIMAAkJYA+vDADKAQAMAAkJYA+vDADKAQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJBAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAABLgAFFH8FAAMWAAMJgwtxPwAAAAADAAIJgwtVygCBAAAWAAEJAABxPwAAAAAAAA==.Frís:BAAALgAECggJEwABLgAFFAMJCQAWADIaAA==.',
Fu='Furryfist:BAAALgADCgcJCAAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIPAAkJiRiEJABAAgAPAAkJiRiEJABAAgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAMJCAAOAJkRAA==.Gilrathor:BAAALgAECggJDgAAAA==.Gizzlit:BAABLgAECn8nAAIMAAgJDhtuCQANAgAMAAgJDhtuCQANAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAECgUJBgAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBveJAA3AgACAAkJsBveJAA3AgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandgoop:BAAALgAECgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8nAAMCAAgJCh7uJgAuAgACAAgJCh7uJgAuAgAdAAUJ+hL5GAA/AQAAAA==.',
Gu='Guppy:BAAALgAECgcJDAAAAA==.Gutcassidy:BAAALgAECgQJCQAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harps:BAAALgAECgUJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAABLgAECn8mAAIXAAgJLwLfQADTAAAXAAgJLwLfQADTAAAAAA==.Heatup:BAABLgAECn8aAAISAAgJfiMzFQApAwASAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8iAAISAAgJphvUSwDgAQASAAgJphvUSwDgAQAAAA==.Holymonka:BAAALgAECgEJAQAAAA==.Homtardy:BAABLgAECn8YAAIeAAYJpx1KJABYAQAeAAYJpx1KJABYAQAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgAECgYJBgABLgAECgkJJwAKABcgAA==.',
Ik='Iknowaguy:BAAALgADCgEJAQABLgAECgkJNwAVAGMSAA==.',
Il='Ilyanna:BAABLgAECn8lAAMfAAkJgh2VBAAuAgAfAAkJgh2VBAAuAgAPAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8eAAQdAAgJ9xfIAQAJAgAdAAcJPBTIAQAJAgAgAAYJARqKBgC3AQACAAMJCxnaIgBaAAAuAAQKfyUAAiAACAmyJDgGADkDACAACAmyJDgGADkDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgQJBAAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJNwAVAGMSAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMhAAYJlx1rDwDkAQAhAAYJlx1rDwDkAQAaAAQJjQ/BZQB/AAAAAA==.',
Ji='Jiinxx:BAAALgAECgIJAwAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgYJCgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerafyrm:BAABLgAECn87AAMZAAgJwx/PBADDAgAZAAgJwx/PBADDAgAaAAUJsBtPOAArAQAAAA==.Kerrigan:BAACLgAFFH8jAAIbAAcJew3/GACrAQAbAAcJew3/GACrAQAuAAQKfzMAAhsACQn4HuoTAJACABsACQn4HuoTAJACAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAiAAEJPRBUMQA+AAAAAA==.Kozand:BAAALgAECgQJBAABLgAECgYJFQAMANIPAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgADCggJFwAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMhAAkJgxlNDAAWAgAhAAcJQRpNDAAWAgAaAAUJFxiwPgAOAQAAAA==.Kyralen:BAABLgAECn8cAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAKAAIJVxNNKQFkAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgcJDwAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8WAAIJAAcJmyE5AwA/AgAJAAcJmyE5AwA/AgAuAAQKfy0AAgkACQnqJSUBAK0DAAkACQnqJSUBAK0DAAAA.Lividea:BAAALgAECgUJEgAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8WAAIYAAgJ8A6EMwBLAQAYAAgJ8A6EMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCAAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMLAAMJ1x1LKgAXAQALAAMJ1x1LKgAXAQAMAAEJowGrFQA0AAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAcJFAAbAHUbAA==.Magicmanzz:BAABLgAECn8aAAISAAgJiQ1dcQB9AQASAAgJiQ1dcQB9AQAAAA==.Magnifuso:BAAALgAECgYJEAAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAINAAMJIRd4KQDEAAANAAMJIRd4KQDEAAAuAAQKfy4AAw0ACQnbH/cWADwCAA0ABwkNH/cWADwCAAoACAntGbw+APMBAAAA.',
Mc='Mcplucky:BAAALgAECgQJCQAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Miguelito:BAAALgAECgEJAQABLgAECgcJFwAhALwcAA==.Mikio:BAABLgAECn8eAAIBAAkJcQ/mIACnAQABAAkJcQ/mIACnAQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIXAAkJLRyRCQC5AgAXAAkJLRyRCQC5AgAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIPAAYJPxW+cgB5AQAPAAYJPxW+cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8OAAILAAYJiBC1EgCeAQALAAYJiBC1EgCeAQAuAAQKfywAAwsACAl+HJ4ZAEoCAAsACAl+HJ4ZAEoCABwAAQlxDx+TADEAAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Naturals:BAAALgAECgEJAwAAAA==.Navillus:BAACLgAFFH8gAAIZAAcJhhC8CQDiAQAZAAcJhhC8CQDiAQAuAAQKf0cAAxkACQnvFMEMAGoCABkACQnvFMEMAGoCACEABwkHItwIAFUCAAAA.',
No='Norasoul:BAABLgAECn8wAAMbAAkJ5huxFQCCAgAbAAkJ5huxFQCCAgAjAAcJ2BR+DAB0AQAAAA==.',
Og='Ogron:BAACLgAFFH8aAAMLAAQJJiYwDwC7AQALAAQJJiYwDwC7AQAcAAEJcx/FGwBTAAAuAAQKfzkAAxwACQl8JRAEAF4DABwACQl8JRAEAF4DAAsAAwknIEeIAKcAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgADCgQJBAAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8JAAIDAAQJMR1fNQBpAQADAAQJMR1fNQBpAQAuAAQKfywAAgMACQliJDoEAFQDAAMACQliJDoEAFQDAAAA.Orwenya:BAABLgAECn8VAAIMAAYJ0g9VGgAIAQAMAAYJ0g9VGgAIAQAAAA==.',
Os='Osten:BAAALgAECggJEwAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Po='Porkit:BAAALgAFFAIJAgAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAABLgAFFH8FAAIkAAIJfAzyKACKAAAkAAIJfAzyKACKAAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8eAAIBAAgJ1hjAAQAAAgABAAgJ1hjAAQAAAgAuAAQKfzsAAgEACQnBJqcAAIQDAAEACQnBJqcAAIQDAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJGAAbAEUjAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8nAAIeAAgJVByMDQA3AgAeAAgJVByMDQA3AgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn8pAAIeAAgJiiEBBwClAgAeAAgJiiEBBwClAgAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMTAAYJ5A8zCQBZAQATAAYJ5A8zCQBZAQASAAYJown/xwDeAAAAAA==.',
['Rè']='Rènza:BAAALgAFFAMJBAAAAA==.',
Sa='Saelybrosa:BAAALgAECgcJDAAAAA==.Samsara:BAAALgAECgQJBwAAAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgQJBQAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAFFAIJAwAFAAAAAA==.Shadda:BAABLgAECn8UAAIlAAYJ/BVtIgAWAQAlAAYJ/BVtIgAWAQAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIcAAIJXg38OACAAAAcAAIJXg38OACAAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgcJDgAFAAAAAA==.Shinru:BAABLgAECn8WAAMNAAkJbhj2KACvAQANAAgJCxf2KACvAQAKAAYJlh5ciABEAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8JAAIWAAMJMhopHADdAAAWAAMJMhopHADdAAAAAA==.',
Si='Sickdayze:BAABLgAECn8cAAINAAkJcR5ACwDEAgANAAkJcR5ACwDEAgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sikkunt:BAAALgAECgEJAwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgAECgQJBAAAAA==.',
Sl='Slootin:BAAALgAECgEJAgAAAA==.Slyxxar:BAACLgAFFH8LAAILAAMJTg0hRwCzAAALAAMJTg0hRwCzAAAuAAQKfxwABAwACAkaFzEPAJ8BAAwACAkaFzEPAJ8BABwABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smarc:BAABLgAECn87AAIdAAkJsh4WBADlAgAdAAkJsh4WBADlAgAAAA==.Smashtokhan:BAAALgAECgUJCAAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8TAAIEAAcJpxiiBgBeAgAEAAcJpxiiBgBeAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFm95AD0AAAAA.Sophie:BAACLgAFFH8OAAMKAAQJwCH8GAB9AQAKAAQJwCH8GAB9AQANAAEJ2w3rQQA4AAAuAAQKfxsAAwoACAmqHJpHANgBAAoACAmqHJpHANgBAA0ABgkuDlNKAE8BAAEuAAUUBwkTAAQApxgA.Sophievokie:BAAALgAECgQJCwABLgAFFAcJEwAEAKcYAA==.Sophisticate:BAABLgAFFH8QAAIdAAQJnB4SCgBmAQAdAAQJnB4SCgBmAQABLgAFFAcJEwAEAKcYAA==.Sophiz:BAAALgAECgYJDwABLgAFFAcJEwAEAKcYAA==.Sophlax:BAACLgAFFH8TAAIXAAUJLySjAQCpAQAXAAUJLySjAQCpAQAuAAQKfxkAAhcACQnLIA8EABQDABcACQnLIA8EABQDAAEuAAUUBwkTAAQApxgA.Sophs:BAABLgAFFH8FAAILAAMJqxh7OwDaAAALAAMJqxh7OwDaAAABLgAFFAcJEwAEAKcYAA==.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAACLgAFFH8IAAIlAAMJWB+3CgAXAQAlAAMJWB+3CgAXAQAuAAQKfzAAAiUACQkmIUcCAAoDACUACQkmIUcCAAoDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAFAAAAAA==.',
Sp='Spicynoodle:BAABLgAECn8WAAICAAkJShWgJwAqAgACAAkJShWgJwAqAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAABLgAECn8dAAIYAAUJiyXJIQCZAQAYAAUJiyXJIQCZAQAAAA==.',
Sq='Squattinchop:BAABLgAECn8eAAIHAAYJQiH3FQA6AgAHAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAHAEIhAA==.',
St='Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIbAAYJMhFNcwBLAQAbAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEQAFAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiDsDwDbAgADAAkJXiDsDwDbAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8xAAQEAAgJUiFyDgDGAgAEAAcJfCJyDgDGAgABAAIJkA/HZABqAAAlAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgADCgMJAwAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôcôld:BAAALgADCgQJBAAAAA==.',
Ta='Takoda:BAAALgAECggJCgAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAAALgAECggJEwAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thorish:BAABLgAECn8kAAImAAkJ5CGrAwDbAgAmAAkJ5CGrAwDbAgAAAA==.Thrayne:BAAALgADCgIJAgAAAA==.',
Ti='Tiddyweaver:BAAALgAECgYJEAABLgAECgkJHwAZAEcfAA==.Timbit:BAABLgAECn8jAAIHAAgJfQmhMwBTAQAHAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgADCgYJBwAAAA==.Tinybubbles:BAABLgAECn8lAAMLAAgJDhYYQACQAQALAAgJDhYYQACQAQAcAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJEAAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8dAAMnAAkJGxh9FQANAgAnAAkJGxh9FQANAgAYAAEJvweofgArAAAAAA==.',
Tr='Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCwAAAA==.',
Ty='Tyranis:BAEALgAECgUJBgAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8WAAMZAAgJ+A00EwCEAQAZAAgJ+A00EwCEAQAaAAYJRAioWQCmAAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAABLgAECn8iAAIbAAgJRxIfTQCGAQAbAAgJRxIfTQCGAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8oAAMWAAgJphO4IgAiAQADAAYJ5xXfjwBgAQAWAAgJ+g64IgAiAQAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8fAAMoAAgJ+yMEEABmAgAoAAgJ+yMEEABmAgAkAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8GAAIDAAMJBwv/jgDNAAADAAMJBwv/jgDNAAAuAAQKfyQAAgMACQlzFjN0AGcBAAMACQlzFjN0AGcBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8HAAIOAAMJayOWDQAyAQAOAAMJayOWDQAyAQAuAAQKfyMAAg4ABwmGI4oKADMCAA4ABwmGI4oKADMCAAAA.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8hAAIVAAgJDRN5GQCUAQAVAAgJDRN5GQCUAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
Wo='Wokstar:BAAALgAECgEJAQAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhSYJgC/AQANAAkJxhSYJgC/AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAACLgAFFH8HAAIbAAMJEhDnUwDQAAAbAAMJEhDnUwDQAAAuAAQKfyoAAhsACQkYIAwPALgCABsACQkYIAwPALgCAAAA.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8WAAIiAAUJGiC4AACxAQAiAAUJGiC4AACxAQAuAAQKfxYAAiIACAnDInIEANUCACIACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zacariana:BAAALgADCgcJBwAAAA==.Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAAALgAECgcJEQAAAA==.',
Ze='Zelgie:BAABLgAECn8qAAMmAAgJnxGXFQBeAQAmAAgJnxGXFQBeAQANAAUJ6BB0SwD1AAAAAA==.',
Zi='Zimzim:BAABLgAECn8VAAIIAAgJVBGnLACfAQAIAAgJVBGnLACfAQAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAoAN0XAA==.',
Zu='Zulu:BAABLgAECn8VAAIJAAYJkBzFIwB7AQAJAAYJkBzFIwB7AQAAAA==.',
['Zâ']='Zâkârum:BAAALgADCgcJBwAAAA==.',
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
