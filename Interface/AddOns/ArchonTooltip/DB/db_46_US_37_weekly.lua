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

local lookup = {'Druid-Balance','Druid-Restoration','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Mage-Frost','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DeathKnight-Blood','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','DemonHunter-Devourer','Priest-Shadow','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Holy','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','DeathKnight-Frost','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adhoria:BAAALgAECgEJAgAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8dAAMBAAUJhx1kDABgAQABAAQJhx1kDABgAQACAAMJ1BcvJADuAAAuAAQKfy8AAwEACQmLI5QQAJsCAAEACAmOJJQQAJsCAAIACQlAHU8jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8mAAIDAAgJCiPrBAAKAwADAAgJCiPrBAAKAwAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgADCgUJBAAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1QIwCjAQAEAAgJzA1QIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn8mAAIGAAgJ8RNLDQCXAQAGAAgJ8RNLDQCXAQAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAABLgAECn8sAAIHAAkJQgxnSgC5AQAHAAkJQgxnSgC5AQAAAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8PAAMCAAQJgweoJQDmAAACAAQJgweoJQDmAAABAAIJwwLOFwB5AAAuAAQKfyEAAwIACQn2F9AgAPsBAAIACQn2F9AgAPsBAAEAAQlOHUtbAFAAAAAA.',
An='Angando:BAABLgAECn8fAAIIAAgJ6hKsEQB+AQAIAAgJ6hKsEQB+AQAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAABLgAECn8YAAIBAAcJEhFUKAAxAQABAAcJEhFUKAAxAQAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAABLgAECn8pAAQJAAgJ1R/OCABWAgAJAAgJ5B7OCABWAgAKAAYJGiEVIQA/AgALAAEJngr/igAwAAAAAA==.Artishard:BAAALgADCgMJAwAAAA==.',
As='Ashkaari:BAACLgAFFH8MAAIMAAMJog+OMgC6AAAMAAMJog+OMgC6AAAuAAQKfxUAAgwACQl3FmInAPQBAAwACQl3FmInAPQBAAAA.Asuná:BAAALgAECggJEwAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgQJBAAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgIJAgABLgAFFAUJHQABAIcdAA==.',
Ba='Backerrz:BAACLgAFFH8ZAAINAAUJ6A8pHgALAQANAAUJ6A8pHgALAQAuAAQKfzAAAw0ACQlyHMIQAJACAA0ACQlyHMIQAJACAA4AAwlAGS45ANAAAAAA.Bamberk:BAAALgADCgMJAwABLgAECgcJIAANAHEeAA==.',
Be='Bearwidit:BAAALgAECgYJCQAAAA==.Beefbrownie:BAABLgAECn8ZAAIIAAgJPSNSBAChAgAIAAgJPSNSBAChAgAAAA==.Bellezora:BAAALgAECgMJAwABLgAECggJHAACAKITAA==.Berz:BAAALgAECgUJCQAAAA==.Berzerked:BAABLgAECn8vAAIPAAkJbSOsAQAnAwAPAAkJbSOsAQAnAwAAAA==.Bestboygrip:BAAALgAECgYJDAAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAAALgAECgYJEgAAAA==.Bigsave:BAABLgAECn8aAAICAAgJ5Q8UVABXAQACAAgJ5Q8UVABXAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blindem:BAAALgADCgEJAQABLgAECggJHAACAGclAA==.Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8SAAIQAAQJfRbDDwAQAQAQAAQJfRbDDwAQAQAuAAQKf0IAAhAACQlgIGcGAHcCABAACQlgIGcGAHcCAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn8iAAMDAAkJ7hD7HgCjAQADAAkJ7hD7HgCjAQARAAEJYAh3dQAuAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAAALgAECgUJCAAAAA==.',
Bu='Buckett:BAAALgAECgMJAwAAAA==.Buckfuttz:BAAALgAECgYJBwAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH8gAAISAAYJhCVMAACAAgASAAYJhCVMAACAAgAuAAQKfxcAAhIACQlfJngAANkDABIACQlfJngAANkDAAEuAAUUCQkWABMAsSEA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAABLgAECn8bAAIIAAcJgRMNFgBEAQAIAAcJgRMNFgBEAQAAAA==.',
Ch='Chainmalejr:BAAALgAECgYJBgABLgAFFAQJEAAHABYUAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chirón:BAAALgAECgYJBgAAAA==.Chiyukii:BAAALgAECgEJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJKQAGAL0cAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8hAAIKAAgJhxr0MADGAQAKAAgJhxr0MADGAQAAAA==.Cowmein:BAABLgAECn8VAAMBAAYJKAzWOQDSAAABAAYJKAzWOQDSAAACAAEJ4AQj4AAkAAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAABLgAECn8aAAIUAAcJ9RnkLwC9AQAUAAcJ9RnkLwC9AQAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAUJGwAVAAofAA==.',
Da='Dapur:BAAALgADCgkJEgAAAA==.Dayne:BAABLgAECn8YAAISAAcJfwwiLQAXAQASAAcJfwwiLQAXAQAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAQJEAAHABYUAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.Deäthknight:BAAALgADCgEJAQAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8QAAIWAAQJbBpsCwBdAQAWAAQJbBpsCwBdAQAuAAQKfyEAAhYACQnRGTQRACMCABYACQnRGTQRACMCAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgQJBAAAAA==.',
Do='Donald:BAABLgAECn82AAMBAAgJyxLrHQB+AQABAAgJyxLrHQB+AQACAAMJiwdCpwB5AAAAAA==.Doublea:BAAALgAECgcJEAAAAA==.',
Dr='Dragonchest:BAAALgAECgMJAwAAAA==.Dragonswolf:BAABLgAECn8mAAIWAAgJTg9iMwDdAQAWAAgJTg9iMwDdAQAAAA==.Dragonwing:BAAALgAECgEJAQAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgAECgUJBgAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAUJHQADAKolAA==.Dregon:BAACLgAFFH8dAAIDAAUJqiWkBQATAgADAAUJqiWkBQATAgAuAAQKfy0AAwMACQkwJmACAGYDAAMACQkwJmACAGYDABEAAgnlIalaAKUAAAAA.Dreinara:BAAALgAECgUJDQAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Duff:BAAALgADCggJCQAAAA==.Dummysezwhut:BAABLgAECn8bAAIBAAcJRg9qKgAlAQABAAcJRg9qKgAlAQAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ei='Eilyn:BAABLgAECn8qAAIXAAgJDhE6VACDAQAXAAgJDhE6VACDAQAAAA==.',
El='Elesis:BAAALgADCgQJBAAAAA==.Ellida:BAABLgAECn8aAAIVAAcJMxGQIwC7AQAVAAcJMxGQIwC7AQAAAA==.',
Em='Emastoned:BAAALgAECgYJBwAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8iAAMOAAkJPR5GAgBVAgAOAAgJIB9GAgBVAgANAAgJBBrHLADnAQAAAA==.',
Fa='Fangmage:BAAALgAECgYJBwAAAA==.Fayker:BAAALgAECgQJBQAAAA==.Fazlain:BAABLgAECn8cAAIKAAgJXRroIgAIAgAKAAgJXRroIgAIAgAAAA==.',
Fe='Felestis:BAAALgAECgYJCAAAAA==.Felnir:BAAALgAECgEJAQABLgAECggJEwAFAAAAAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAQJDwAYAKwQAA==.',
Fl='Fluffydragon:BAABLgAECn8mAAMZAAkJJxxDAwDYAgAZAAkJJxxDAwDYAgAaAAUJ5wdkKADdAAAAAA==.',
Fr='Friartuck:BAAALgAECgcJCQABLgAECgkJLgAKAI0hAA==.Frosteez:BAAALgAECgEJAQABLgAECgQJEAAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8cAAMCAAgJZyWxAwBZAwACAAgJZyWxAwBZAwAbAAEJXhgfLQBIAAAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Ganden:BAABLgAECn8nAAIBAAgJWxmiEgDuAQABAAgJWxmiEgDuAQAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAABLgAECn8rAAIXAAgJlRdzSwAAAgAXAAgJlRdzSwAAAgAAAA==.Gatelinka:BAAALgAECgYJCQABLgAECgkJJgAZACccAA==.Gateto:BAABLgAECn8nAAMMAAgJ1yDnCQDaAgAMAAgJ1yDnCQDaAgAcAAQJiBCSQgDQAAABLgAECgkJJgAZACccAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJCgAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgADCgcJEAAAAA==.',
Gw='Gwenneth:BAAALgAECgMJAwAAAA==.',
['Gú']='Gúr:BAAALgADCgkJGwAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Healthat:BAAALgADCgEJAQAAAA==.Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8iAAIOAAgJFhTHBgCeAQAOAAgJFhTHBgCeAQAAAA==.Helsreach:BAAALgADCgMJAgAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.',
Hr='Hruoth:BAAALgADCgIJAgAAAA==.',
Hu='Hunt:BAABLgAECn8YAAMKAAYJ1RcbVQBJAQAKAAYJNBcbVQBJAQALAAQJsw3cXQDKAAAAAA==.Huntinbub:BAABLgAECn8rAAMKAAgJiBA9QQCHAQAKAAgJiBA9QQCHAQALAAEJzQAxmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgkJBAAAAA==.',
Ir='Irim:BAAALgAECgMJAwAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAECggJDwABLgAFFAQJEAAWAGwaAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8RAAIUAAUJahd6IwA7AQAUAAUJahd6IwA7AQAuAAQKfyEAAxQACAmJIeARAPACABQACAmJIeARAPACAB0AAglECPthAFoAAAAA.Izlaar:BAAALgADCgkJEwAAAA==.Izzytt:BAAALgAECgUJCQAAAA==.',
Ja='Jacenskie:BAABLgAECn8iAAIWAAkJzBF/IwCJAQAWAAkJzBF/IwCJAQAAAA==.Jacob:BAAALgAECgQJCQAAAA==.Jadedbabe:BAAALgAECgUJBgAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgAECgEJAQABLgAFFAQJEAAHABYUAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Joppa:BAAALgAECgIJAgABLgAECggJDQAFAAAAAA==.Joyvimon:BAAALgAECgYJDwAAAA==.',
Ju='Jugernaut:BAAALgADCgYJDQAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIeAAgJdguvaABLAQAeAAgJdguvaABLAQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJyxuVCwCiAQAEAAYJyxuVCwCiAQAaAAIJEgemBgClAAAuAAQKfxUAAxoACQkBIL4OAO8BAAQABwmCGvgXABMCABoABgnGI74OAO8BAAAA.Khornedaemon:BAAALgAECgEJAQAAAA==.',
Ki='Kickstarter:BAAALgAFFAIJAwAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kiy:BAAALgAECggJCgAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAAALgAECgUJDAAAAA==.Kronas:BAAALgAECgUJCQAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIUAAkJfxu3PAABAgAUAAkJfxu3PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8PAAQYAAQJrBD+FwAiAQAYAAQJFw3+FwAiAQAfAAIJVhSpDACZAAAVAAIJfABxKQA/AAAuAAQKfx8ABB8ACQmAG8UHAKwCAB8ACQmAG8UHAKwCABgABAlUBrE/ALEAABUAAgkgBi5YAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAQJDwAYAKwQAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8dAAIfAAUJEhwZBwB7AQAfAAUJEhwZBwB7AQAuAAQKfy8AAh8ACQnOIKYDAB8DAB8ACQnOIKYDAB8DAAAA.Leomoon:BAAALgAECgMJBAAAAA==.Leshy:BAAALgAECgYJBgAAAA==.Levite:BAABLgAECn8YAAMfAAYJYRqOHgCGAQAfAAUJZxyOHgCGAQAYAAUJGhJkKgAhAQAAAA==.',
Li='Lilara:BAABLgAECn8YAAINAAcJVQjxeAALAQANAAcJVQjxeAALAQAAAA==.Lionknite:BAABLgAECn8pAAIeAAkJsxrqJAAqAgAeAAkJsxrqJAAqAgAAAA==.Liontabu:BAAALgAECgQJBgAAAA==.Liteshocklet:BAAALgAECgEJAgABLgAFFAQJDwAYAKwQAA==.Littledung:BAAALgADCgYJCgAAAA==.',
Lo='Looting:BAABLgAECn8bAAIgAAcJKBI8CQBnAQAgAAcJKBI8CQBnAQAAAA==.',
Lu='Lunexiya:BAAALgAECgkJCQAAAA==.Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAABLgAECn8gAAMCAAgJdgsIXQA7AQACAAgJdgsIXQA7AQAbAAEJKALROwAdAAAAAA==.',
Ma='Mageko:BAAALgAECgEJBgAAAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAABLgAECn8WAAIKAAgJxQtRUABXAQAKAAgJxQtRUABXAQAAAA==.Malvina:BAAALgAFFAEJAQAAAA==.Maoli:BAABLgAECn8UAAMXAAQJkhUutQDIAAAXAAMJoBUutQDIAAAhAAQJHgs/UQCYAAAAAA==.Marohen:BAAALgADCgYJBgAAAA==.Mauka:BAABLgAECn8hAAMBAAgJTBDdOABUAQABAAYJQBTdOABUAQACAAgJwwsVPgBSAQAAAA==.Mauzer:BAAALgAECgEJAQABLgAECgcJJQAdAPwYAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8mAAIeAAkJnRsUMAB3AgAeAAkJnRsUMAB3AgAAAA==.Mcscrotie:BAABLgAECn8UAAIeAAgJQAZbgQAXAQAeAAgJQAZbgQAXAQAAAA==.',
Me='Mes:BAABLgAECn8jAAIcAAkJgRvmEAAZAgAcAAkJgRvmEAAZAgAAAA==.',
Mi='Mimmi:BAAALgAECgUJEAABLgAECgcJJQAdAPwYAA==.Mishri:BAACLgAFFH8HAAIUAAMJhx0mLAAiAQAUAAMJhx0mLAAiAQAuAAQKfzEAAhQACQnQJFgCAEUDABQACQnQJFgCAEUDAAAA.',
Mo='Moonsorrow:BAAALgADCgMJAwAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn8lAAMdAAcJ/Bg8EgCjAQAdAAcJ8Bg8EgCjAQAiAAIJ8RkfIgBCAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMXAAYJPwgLswDMAAAXAAYJPwgLswDMAAAGAAQJ0wIuNgBrAAAAAA==.Myodieboy:BAAALgADCgEJAgAAAA==.',
Na='Nakabeam:BAABLgAECn8mAAIUAAkJAxSnUgA9AQAUAAkJAxSnUgA9AQAAAA==.Nakatwin:BAABLgAECn8YAAIUAAcJJhXmWACXAQAUAAcJJhXmWACXAQABLgAECgkJJgAUAAMUAA==.Naklek:BAABLgAECn8hAAMbAAgJBh6TBgCOAgAbAAgJBh6TBgCOAgATAAEJYgtiNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8OAAIKAAUJFxtvGwBEAQAKAAUJFxtvGwBEAQAuAAQKfyMAAwoACQmsH5sOAMYCAAoACQmsH5sOAMYCAAsABAl0BlRpAJkAAAAA.Nika:BAAALgAECgYJCQAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8hAAMfAAgJ9weKKQAxAQAfAAgJ9weKKQAxAQAVAAEJ0wHeawAaAAAAAA==.',
No='Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAAALgAECggJEwAAAA==.',
Or='Orcdung:BAAALgADCgEJAQAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAAALgAECgcJEgABLgAECggJFgASAEMXAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgADCgkJCQABLgAFFAQJEAAWAGwaAA==.Panzerfäust:BAAALgAECgQJEAAAAA==.Pawrina:BAAALgAECgkJEQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgADCgMJAwAAAA==.Pestis:BAAALgADCgkJDwAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8jAAMXAAgJaxITWAB5AQAXAAgJaxITWAB5AQAhAAQJzgh2TwCgAAAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAABLgAECn8UAAIfAAcJZhZOGwCjAQAfAAcJZhZOGwCjAQAAAA==.Punchem:BAAALgADCgcJBwAAAA==.Purex:BAABLgAECn8dAAIgAAkJKQYwCgCSAQAgAAkJKQYwCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgEJAQAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIGAAgJ3xqNCAD0AQAGAAgJ3xqNCAD0AQAAAA==.Rathus:BAABLgAECn8gAAINAAcJcR7ELwBOAgANAAcJcR7ELwBOAgAAAA==.Rawdata:BAACLgAFFH8IAAIMAAMJSgk2NACzAAAMAAMJSgk2NACzAAAuAAQKfygAAyMACQk4FQ0KALMBACMACQk4FQ0KALMBAAwACAkvD1RCAHgBAAAA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIKAAgJqRetPQC4AQAKAAgJqRetPQC4AQAAAA==.Rebeka:BAABLgAECn8cAAIhAAgJ2R3BCgCYAgAhAAgJ2R3BCgCYAgABLgAECggJIAAKAKkXAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEQABLgAECgcJGAASAH8MAA==.Reniel:BAAALgADCgYJBgABLgAECggJJgAGAPETAA==.Ressie:BAAALgAECgQJCQAAAA==.Reston:BAAALgAECgYJBgABLgAECggJIgADAF0iAA==.Reverendlion:BAABLgAECn8UAAIVAAgJtxUvFwC9AQAVAAgJtxUvFwC9AQAAAA==.',
Ri='Riyu:BAAALgADCgEJAgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAAALgAFFAEJAQABLgAFFAMJDQAXAJAPAA==.',
Sa='Saiko:BAAALgAECgMJAwAAAA==.Sainthealz:BAAALgAECgEJAQAAAA==.Saladcake:BAABLgAECn8XAAIHAAcJPhKccgBVAQAHAAcJPhKccgBVAQAAAA==.Salleane:BAABLgAECn8YAAIXAAgJthUzXgDJAQAXAAgJthUzXgDJAQAAAA==.Sampal:BAABLgAECn8uAAMGAAkJ+xnpBgAeAgAGAAgJrxzpBgAeAgAXAAEJFAdkNgEzAAAAAA==.Sampriest:BAABLgAECn8bAAMfAAcJjh8uDABYAgAfAAcJjh8uDABYAgAYAAEJpxCeUwA4AAABLgAECgkJLgAGAPsZAA==.Samwield:BAACLgAFFH8PAAIkAAQJaCC8CAB3AQAkAAQJaCC8CAB3AQAuAAQKfzwABCQACQnIIZcCAPACACQACQnIIZcCAPACACAAAwlCGEsTAM0AACUAAQnUCoQZADAAAAAA.Sanchoe:BAAALgAECgcJDAAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.',
Se='Seireitei:BAABLgAECn8pAAIMAAkJ5hkTDwCKAgAMAAkJ5hkTDwCKAgAAAA==.Selaheal:BAABLgAECn8sAAIVAAkJPhaYEAAFAgAVAAkJPhaYEAAFAgAAAA==.Seraath:BAACLgAFFH8dAAIiAAUJkhsdAgAyAQAiAAUJkhsdAgAyAQAuAAQKfyYAAyIACQn3IZAAAGQDACIACQn3IZAAAGQDABQAAQkAAJDSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.',
Sh='Shadowskull:BAAALgADCgcJEwAAAA==.Shadwkllr:BAAALgAECgQJDgAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAAALgAECgYJDwAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skid:BAAALgADCgEJAQAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Sneakyhoof:BAAALgADCgcJBwAAAA==.Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgAECgYJDAAAAA==.',
St='Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBAAAAA==.Stervana:BAACLgAFFH8IAAIEAAQJjxqgFQBBAQAEAAQJjxqgFQBBAQAuAAQKfy0AAgQACQl0IOIDAFoDAAQACQl0IOIDAFoDAAAA.Sterzephyr:BAAALgAECgYJBgABLgAFFAQJCAAEAI8aAA==.Stickytoes:BAAALgADCgYJBgAAAA==.Stormyknight:BAABLgAECn8rAAMZAAkJ3g4kEAB9AQAZAAkJ3g4kEAB9AQAaAAcJOwv3DQDnAAAAAA==.',
Su='Sundemonhunt:BAAALgAECgMJAwAAAA==.Sunpally:BAAALgAECgIJAgAAAA==.Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8KAAIHAAMJmxJkLwD5AAAHAAMJmxJkLwD5AAABLgAFFAUJHAAIAOEjAA==.Suswar:BAACLgAFFH8cAAIIAAUJ4SNtBQCDAQAIAAUJ4SNtBQCDAQAuAAQKfzAAAggACQnIJJoAALgDAAgACQnIJJoAALgDAAAA.Suvulaan:BAABLgAECn8tAAMZAAgJ/AeWFgAZAQAZAAcJ3geWFgAZAQAEAAUJcgNeVQCAAAAAAA==.',
Sw='Swifix:BAAALgAECgYJBgAAAA==.',
Ta='Tacostand:BAACLgAFFH8XAAIUAAUJERa/EABJAQAUAAUJERa/EABJAQAuAAQKfy8AAhQACQlNIOUHAEwDABQACQlNIOUHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAABLgAECn8uAAIKAAkJjSGaCADWAgAKAAkJjSGaCADWAgAAAA==.',
Te='Teeice:BAABLgAECn8fAAIgAAkJFBFNBQDeAQAgAAkJFBFNBQDeAQAAAA==.Teo:BAABLgAECn8cAAIVAAgJURIOGwCYAQAVAAgJURIOGwCYAQAAAA==.Terian:BAAALgAECgkJBQAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIcAAkJABG6JwBYAQAcAAkJABG6JwBYAQAAAA==.Thekan:BAABLgAECn8bAAIdAAkJlxTCDAD3AQAdAAkJlxTCDAD3AQAAAA==.Theriot:BAABLgAECn8qAAQXAAkJmhuwKAAWAgAXAAkJmhuwKAAWAgAGAAYJBwwPHgDNAAAhAAEJMwhHoAAoAAAAAA==.Thianá:BAAALgAECgcJEgAAAA==.Thüclides:BAAALgAECgcJCAAAAA==.',
Ti='Tiermoghuen:BAAALgAECgEJAQAAAA==.Tikidragoona:BAAALgAECgIJAgAAAA==.Timtamslam:BAAALgADCgMJAwAAAA==.Tinkerspell:BAABLgAECn8cAAICAAgJohNnLgCjAQACAAgJohNnLgCjAQAAAA==.Tinkiebella:BAAALgADCgMJAwABLgAECggJHAACAKITAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
To='Tobivoker:BAAALgAECgEJAQAAAA==.Toosus:BAABLgAFFH8PAAIQAAQJVSHxDwAPAQAQAAQJVSHxDwAPAQABLgAFFAUJHAAIAOEjAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAIjAAQJYQdQBQAVAQAjAAQJYQdQBQAVAQAuAAQKfxoAAiMACAkrFG0KACoCACMACAkrFG0KACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgIJAwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgUJCgAAAA==.',
Tr='Trolldung:BAAALgADCgkJEQAAAA==.Truffaut:BAAALgADCgUJBgAAAA==.',
Tt='Tturtle:BAACLgAFFH8NAAIXAAQJxAghLgAfAQAXAAQJxAghLgAfAQAuAAQKfyUAAhcACQl+Fd8wAF8CABcACQl+Fd8wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgYJCAAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAAALgAECgYJBgABLgAFFAQJDwAkAGggAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8YAAIHAAUJBwoAwgDFAAAHAAUJBwoAwgDFAAAAAA==.Verdugo:BAAALgAECgMJBgAAAA==.Verite:BAABLgAECn8VAAMeAAcJsAN51wDSAAAeAAcJqwJ51wDSAAAmAAMJOgUEFABTAAAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8fAAIWAAkJ9BsXCwBuAgAWAAkJ9BsXCwBuAgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgADCgQJBAAAAA==.Voidedge:BAABLgAECn8lAAMOAAcJxQ8JFADKAAANAAcJjQ0YdgBxAQAOAAUJBxEJFADKAAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
We='Wes:BAABLgAECn8vAAIgAAkJoxlkAgBzAgAgAAkJoxlkAgBzAgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAcJGgAeAL0iAA==.Willybwankin:BAACLgAFFH8aAAIeAAcJvSKbAABrAgAeAAcJvSKbAABrAgAuAAQKfykAAh4ACQkxJsoAAOEDAB4ACQkxJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAABLgAECn8UAAIGAAgJIAz3IQD4AAAGAAgJIAz3IQD4AAAAAA==.',
Wy='Wyvern:BAABLgAECn8VAAINAAcJBg4rYgA9AQANAAcJBg4rYgA9AQAAAA==.',
Xa='Xanthion:BAAALgAECgUJCAAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAAALgAECgQJCgAAAA==.Zalarian:BAAALgAECgUJBQABLgAECgkJNwAHANodAA==.Zalmage:BAABLgAECn83AAMHAAkJ2h2OEwCtAgAHAAkJ2h2OEwCtAgAnAAIJ5wlqFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgYJCAAAAA==.Zeseroth:BAACLgAFFH8ZAAIXAAUJjCBpBwB7AQAXAAUJjCBpBwB7AQAuAAQKfycAAhcACQmkIywDAKMDABcACQmkIywDAKMDAAAA.Zeserotho:BAAALgAECgQJBgAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIfAAQJ1SSWBQCaAQAfAAQJ1SSWBQCaAQAuAAQKfyUAAx8ACQndIBEGAO4CAB8ACQndIBEGAO4CABUABAllE2JRAGMAAAAA.',
['Äs']='Äshra:BAAALgADCgMJAwAAAA==.',
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
