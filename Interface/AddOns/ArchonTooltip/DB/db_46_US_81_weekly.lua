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

local lookup = {'Shaman-Restoration','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Monk-Brewmaster','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','Priest-Shadow','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Devastation','Druid-Guardian','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Warrior-Fury','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Rogue-Subtlety','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw','Evoker-Preservation',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aarmorr:BAABLgAECn82AAIBAAkJkhG7LQDRAQABAAkJkhG7LQDRAQAAAA==.Aatus:BAAALgADCgUJBQAAAA==.',
Ab='Absoul:BAAALgADCgEJAQAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aedelas:BAAALgAECgEJAQAAAA==.Aeloriá:BAABLgAECn8yAAMCAAkJUhvzDwCzAgACAAkJUhvzDwCzAgADAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECgcJDAAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgMJAwAAAA==.Airad:BAAALgADCgUJBgAAAA==.',
Al='Alchon:BAABLgAECn8kAAIEAAkJ6xoOIgAyAgAEAAkJ6xoOIgAyAgAAAA==.Aldera:BAABLgAECn8eAAIBAAkJ3QRQVgAmAQABAAkJ3QRQVgAmAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8jAAMFAAkJwRyOOgDzAQAFAAkJwRyOOgDzAQAGAAEJyhBgFgA3AAAAAA==.Alista:BAAALgADCgUJCgAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn84AAMCAAcJYBZhLwDCAQACAAcJYBZhLwDCAQAHAAIJmQozZgBUAAAAAA==.Alorris:BAAALgAECgQJBAABLgAECggJFwAIACIiAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgcJDAAAAA==.Alyra:BAAALgADCgYJBgAAAA==.',
Am='Amata:BAAALgAECgQJBAAAAA==.Ammastary:BAAALgAECgQJBgAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECggJJgAJAPoZAA==.Andragos:BAAALgAECgQJBgAAAA==.Andrea:BAABLgAECn81AAIDAAkJlBeRBwAsAgADAAkJlBeRBwAsAgAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgADCgcJEgAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJDwAAAA==.Asura:BAAALgAECgEJAQAAAA==.Asyllaa:BAABLgAECn8eAAMKAAkJFx8kIgBeAgAKAAcJOyMkIgBeAgALAAYJ9hJaGgAZAQAAAA==.',
At='Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAAALgAECgIJBAABLgAECgkJHQAMANwcAA==.',
Au='Aumaril:BAAALgAECggJCwAAAA==.Auralynn:BAABLgAECn8dAAIKAAkJpAhwdABlAQAKAAkJpAhwdABlAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averus:BAABLgAECn82AAIHAAkJfw0PIQCTAQAHAAkJfw0PIQCTAQAAAA==.',
Az='Azariel:BAABLgAECn81AAIKAAkJixPBSADNAQAKAAkJixPBSADNAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn8wAAILAAkJ2RyCBACOAgALAAkJ2RyCBACOAgAAAA==.',
Ba='Baane:BAAALgAECgQJBAABLgAECgUJCwANAAAAAA==.Babnik:BAEALgAECgYJEwAAAA==.Bagel:BAACLgAFFH8RAAIOAAQJVCFnEAB6AQAOAAQJVCFnEAB6AQAuAAQKfxkAAw4ACAmCH1AmAPYBAA4ACAmCH1AmAPYBAAoAAQnkCg5jATEAAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn82AAMIAAkJnheLDQBpAgAIAAkJ5RaLDQBpAgAPAAMJFBx6VQDgAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgADCgcJCwAAAA==.Belovis:BAACLgAFFH8OAAIKAAQJSB8iGgBqAQAKAAQJSB8iGgBqAQAuAAQKfyYAAgoACQk0JIwNAN4CAAoACQk0JIwNAN4CAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJLAAOAG4PAA==.',
Bi='Bidoof:BAABLgAECn8ZAAIQAAcJNAWALwDOAAAQAAcJNAWALwDOAAAAAA==.Bigblunt:BAAALgADCgQJBgAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgUJDwAAAA==.',
Bo='Boggrog:BAAALgAECgMJAwABLgAECgQJBAANAAAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn8kAAIRAAgJHAflQgD4AAARAAgJHAflQgD4AAAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ4xUNDAB9AQASAAgJ4xUNDAB9AQAEAAYJ2QqVuACTAAAAAA==.',
Br='Braelyne:BAABLgAECn8WAAIKAAYJdR3JXwDEAQAKAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJDQAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDQAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Burlycheeks:BAABLgAECn85AAIKAAkJPCDFEADHAgAKAAkJPCDFEADHAgAAAA==.',
Ca='Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJCQAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAAALgAECgUJDAAAAA==.Catsneverdie:BAAALgAECgMJDAABLgAFFAMJBgAFAGQFAA==.Catzinhatz:BAAALgAECgcJEAABLgAFFAMJBgAFAGQFAA==.',
Ce='Cecelya:BAABLgAECn8xAAMPAAkJ5RkMEgApAgAPAAkJ5RkMEgApAgAIAAMJUw0TSQCeAAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAIRAAYJNBC2RQAyAQARAAYJNBC2RQAyAQABLgAECgkJFgAQANgbAA==.Chillykiller:BAAALgAECgYJBgABLgAECgkJFgAQANgbAA==.Chiva:BAAALgAECgQJBAABLgAECggJJAABANkdAA==.Chivactdl:BAAALgAECgEJAQABLgAECggJJAABANkdAA==.Chozen:BAAALgAECgcJCgAAAA==.Chunknoriss:BAABLgAECn8ZAAMTAAYJSRucIQDKAQATAAYJSRucIQDKAQAUAAIJ6gSXdQBBAAABLgAECggJJAABANkdAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAECgkJJwABAAAYAA==.Clurefu:BAABLgAECn8tAAMTAAkJsh9ZBgAQAwATAAkJsh9ZBgAQAwAUAAMJ5BZVWACuAAAAAA==.Clurelock:BAABLgAECn8YAAICAAgJLCFICwDsAgACAAgJLCFICwDsAgABLgAECgkJLQATALIfAA==.Cluremage:BAAALgAECgYJCAAAAA==.',
Co='Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAAALgAECgcJEQAAAA==.Constella:BAAALgADCgUJBQAAAA==.Coppertan:BAAALgADCggJDAAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8bAAIVAAgJXhjWCwC/AQAVAAgJXhjWCwC/AQAAAA==.',
Cr='Crazyshammy:BAAALgAECggJEAAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crunchynuget:BAAALgAECgcJEQABLgAFFAQJDAAKAEIbAA==.',
Ct='Cthuwu:BAAALgADCgcJDgABLgAFFAUJCQAEAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.',
Cv='Cvhamster:BAAALgADCgQJBAAAAA==.',
Cy='Cybeast:BAABLgAECn8nAAIDAAkJxBsHBgBaAgADAAkJxBsHBgBaAgAAAA==.Cynortas:BAAALgAECgIJBQAAAA==.',
Da='Daciana:BAAALgAECgYJEgAAAA==.Dados:BAABLgAECn8wAAMPAAkJXh6/CgCUAgAPAAkJXh6/CgCUAgAWAAEJsBQ3aAA/AAAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgADCgkJGAAAAA==.Dambrien:BAAALgAECgEJAQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgADCgEJAQAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8oAAIKAAkJtR8DEQDFAgAKAAkJtR8DEQDFAgAAAA==.Darloct:BAAALgAECgQJCgAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8cAAMQAAcJLBnxJwCDAQAQAAYJexvxJwCDAQAXAAcJFw8gbAAlAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJHAAQACwZAA==.Deadslinger:BAAALgADCgUJBgAAAA==.Deathcat:BAACLgAFFH8GAAIFAAMJZAXSSwBvAAAFAAMJZAXSSwBvAAAuAAQKfzkAAgUACQnKFZ4wABkCAAUACQnKFZ4wABkCAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8PAAMFAAQJZx5AMwBdAQAFAAQJQh5AMwBdAQAGAAIJhB1XEACmAAAAAA==.Deathshadowx:BAAALgAECgQJBAAAAA==.Delryth:BAAALgADCgkJCQAAAA==.Demonkoh:BAAALgAECgUJCAAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgADCgIJAgABLgAECggJGQAUAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn8kAAIWAAgJfA2SJwBoAQAWAAgJfA2SJwBoAQAAAA==.',
Do='Dolemite:BAABLgAECn8rAAMTAAYJUw7APwAWAQATAAYJUw7APwAWAQAUAAUJ7ApLSgCuAAAAAA==.Donalbain:BAABLgAECn8nAAIBAAkJABjbGgBHAgABAAkJABjbGgBHAgAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgADCgYJBgABLgAECgQJBQANAAAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAAALgAECgYJDgAAAA==.',
Du='Durock:BAAALgAECgMJAwAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Eldinn:BAAALgADCgcJBgAAAA==.Elenora:BAAALgADCgEJAQAAAA==.Elidor:BAAALgAECgMJBgAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn8xAAIYAAkJ/xc1CwAuAgAYAAkJ/xc1CwAuAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAAALgAECgYJCgAAAA==.Emmils:BAABLgAECn8sAAIHAAkJWQq3KgBOAQAHAAkJWQq3KgBOAQAAAA==.Emìly:BAABLgAECn85AAQUAAgJkiNuBgDEAgAUAAgJkiNuBgDEAgAJAAUJRRVPPQDnAAATAAQJqAu5ZwB9AAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIZAAUJbw+lAwAuAQAZAAUJbw+lAwAuAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAABLgAECn84AAQKAAgJyiGPGQCMAgAKAAgJyiGPGQCMAgALAAcJMR9ACgD5AQAOAAYJtQxQUADLAAAAAA==.',
Ep='Episkey:BAABLgAECn8bAAMHAAkJyw4oIgCKAQAHAAkJyw4oIgCKAQACAAQJdReXVgAUAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Eropor:BAAALgAECgUJEAABLgAECgkJUgACABIeAA==.Eroversion:BAABLgAECn9SAAUCAAkJEh6kEwCMAgACAAkJEh6kEwCMAgAHAAQJNRQ+VADVAAADAAMJuA09JwCYAAAaAAEJAAD+aQAAAAAAAA==.',
Es='Esmay:BAABLgAECn8YAAIRAAcJoA8iOgBmAQARAAcJoA8iOgBmAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn81AAIbAAkJYQxoBwC9AQAbAAkJYQxoBwC9AQAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgAECgEJAQAAAA==.',
Fi='Filgulfin:BAABLgAECn88AAMEAAkJ7BuGDwCtAgAEAAkJ7BuGDwCtAgASAAgJgRAnEAAxAQAAAA==.Finkate:BAAALgAECggJCAAAAA==.Firebad:BAABLgAECn8wAAMcAAkJpxzFAQCXAgAcAAkJpxzFAQCXAgAdAAYJHwr/yACeAAAAAA==.Firebringer:BAABLgAECn89AAIXAAkJFwsjTAB/AQAXAAkJFwsjTAB/AQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJGwAeAOAWAA==.',
Fl='Flamehunter:BAABLgAECn8iAAMXAAkJMRqEHACnAgAXAAkJcRmEHACnAgAQAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn8/AAMWAAkJshfJDQBUAgAWAAkJshfJDQBUAgAPAAMJSAe7TACAAAAAAA==.Floki:BAAALgAECggJEgAAAA==.Flowing:BAAALgAECgUJBQAAAA==.',
Fo='Foods:BAACLgAFFH8HAAMfAAMJIgkSHQCKAAAfAAMJIgkSHQCKAAAgAAEJLwTWJQAsAAAuAAQKf0QABB8ACQnAF7kVAB0CAB8ACQmOF7kVAB0CACAABwl6EuAaADgBACEAAwnoDGhHAHEAAAAA.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
Ga='Gaboo:BAAALgAECggJDwAAAA==.',
Gh='Ghostinhale:BAAALgAECgUJDAAAAA==.',
Gi='Gilorion:BAAALgAECggJEgAAAA==.',
Gl='Glasgoww:BAAALgAECgMJAwABLgAECgkJJwABAAAYAA==.',
Gn='Gnibat:BAAALgAECgMJAwAAAA==.',
Go='Goburina:BAACLgAFFH8JAAIBAAQJegdKMgDkAAABAAQJegdKMgDkAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grievo:BAAALgAECgYJCAAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAABLgAECn8rAAIEAAkJpRoqHwBCAgAEAAkJpRoqHwBCAgAAAA==.',
Ha='Halcyndraag:BAABLgAECn82AAMiAAkJahLXIgCiAQAiAAcJqRHXIgCiAQAZAAMJ7xWRKADcAAAAAA==.Handbannana:BAAALgADCgcJBwAAAA==.Handsome:BAAALgAECgYJBgABLgAECggJDgANAAAAAA==.Happydk:BAACLgAFFH8PAAMFAAQJniA9HgCYAQAFAAQJniA9HgCYAQAYAAMJKRHUHgCwAAAuAAQKfycAAwUACQnbILMYAJECAAUACQnaHrMYAJECABgABwlKGYYfACgBAAAA.Hartu:BAABLgAECn84AAIgAAkJuw+2EgCXAQAgAAkJuw+2EgCXAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8FAAIjAAIJOhkDIwC1AAAjAAIJOhkDIwC1AAAuAAQKfywAAyMACQmFIT4JAG4CACMACQnyID4JAG4CABsABAnwGtUNACoBAAAA.Hemmorage:BAAALgAECgYJCgABLgAECgkJKQAFANUeAA==.Herbalmist:BAAALgAECgQJBAAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Holysea:BAAALgAECgYJBgABLgAECgkJLAAOAG4PAA==.Horatio:BAAALgAECgEJAQABLgAECgkJJwABAAAYAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAECgkJIAAEALocAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Id='Idiocracy:BAAALgAECgcJDgAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgMJBAAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgQJBAAAAA==.Irys:BAAALgADCgcJDwAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8PAAIEAAUJYCLnEACAAQAEAAUJYCLnEACAAQAuAAQKfxwAAgQACQmXI+cEAD8DAAQACQmXI+cEAD8DAAAA.Ismokeu:BAABLgAECn8rAAIPAAgJvhi6FQD+AQAPAAgJvhi6FQD+AQAAAA==.Ismyn:BAAALgADCgEJAgAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAAALgAECggJEAAAAA==.Jalidelo:BAABLgAECn84AAMIAAkJWxzqBwDSAgAIAAkJWxzqBwDSAgAPAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIdAAkJMhrkIgA8AgAdAAkJMhrkIgA8AgAAAA==.Jokers:BAAALgAECgYJCwAAAA==.Jokersfists:BAAALgAECgYJCgAAAA==.Joranbragi:BAAALgAECgYJEQAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIkAAYJsRCBDgBJAQAkAAYJsRCBDgBJAQAAAA==.Jotoonice:BAAALgAECgYJEgAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8NAAQlAAUJahb/DABGAQAlAAQJ3xP/DABGAQAEAAEJfg6AegBCAAASAAIJrQF1LQA8AAAuAAQKfykABCUACAkPHx0TAPQBABIACAn9F60gACACACUABgmXIh0TAPQBAAQAAglIITKpALQAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAICAAkJZR82BwApAwACAAkJZR82BwApAwAAAA==.Kaana:BAABLgAECn81AAIEAAkJ0RRVLAACAgAEAAkJ0RRVLAACAgAAAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAABLgAECn8VAAIKAAYJ4BNYhQBEAQAKAAYJ4BNYhQBEAQAAAA==.Karungash:BAACLgAFFH8LAAMdAAQJqgq+SgAMAQAdAAQJqgq+SgAMAQAcAAEJVQE+GwA+AAAuAAQKfx0AAx0ACAm1Id4QAPMCAB0ACAm1Id4QAPMCABwAAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIMAAkJzBrmBAA+AgAMAAkJzBrmBAA+AgAAAA==.Karvy:BAAALgAECggJDwABLgAECgkJJAAMAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAQJDQADAOkfAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8OAAIRAAQJAx5uEABbAQARAAQJAx5uEABbAQAuAAQKfyUAAxEACQlhHnERADwCABEACQlhHnERADwCABUAAgn1GgMqAEwAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAQJDgARAAMeAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8VAAIXAAcJBx63MQDfAQAXAAcJBx63MQDfAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgEJAQABLgAECggJEAANAAAAAA==.Kickingdonut:BAACLgAFFH8FAAIUAAMJNx+yEwD+AAAUAAMJNx+yEwD+AAAuAAQKfywAAxQACAk7IxkJAOcCABQACAk7IxkJAOcCAAkABgn1GUI3AG4BAAAA.Killerhottie:BAAALgADCgEJAQAAAA==.Killermoomoo:BAAALgAECgQJBAAAAA==.Kittykarma:BAAALgAECgEJAQAAAA==.',
Kl='Kloverr:BAAALgADCgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgADCgEJAQAAAA==.Kombatkarl:BAAALgADCgMJAwAAAA==.',
Kr='Kromir:BAAALgADCgkJHQAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgQJBgAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krum:BAACLgAFFH8RAAIKAAQJbhn4IQBPAQAKAAQJbhn4IQBPAQAuAAQKfx4AAgoACAmsHYo/AOkBAAoACAmsHYo/AOkBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn8/AAIKAAkJLBlfIQBiAgAKAAkJLBlfIQBiAgAAAA==.Laurian:BAAALgADCgcJDwAAAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8FAAIaAAIJdRlPFACaAAAaAAIJdRlPFACaAAAuAAQKf0MAAxoACQktHZQEAJ4CABoACQktHZQEAJ4CAAMAAwl9DtkmAJsAAAAA.Leftblank:BAAALgAECgQJBAAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgMJBgABLgAECgMJBgANAAAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Ly='Lychi:BAAALgAECgQJBAAAAA==.Lylora:BAACLgAFFH8KAAICAAMJjh/QIQAbAQACAAMJjh/QIQAbAQAuAAQKfz4AAgIACQlKJJMBALEDAAIACQlKJJMBALEDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8jAAMPAAgJGhDOJAB6AQAPAAgJGhDOJAB6AQAWAAUJAgWGVwB5AAAAAA==.',
Ma='Madesh:BAABLgAECn81AAMXAAkJSRqNIAA0AgAXAAkJSRqNIAA0AgAMAAkJRhPQBwDVAQAAAA==.Madman:BAABLgAECn8hAAITAAgJsQ7fLgBvAQATAAgJsQ7fLgBvAQAAAA==.Maelle:BAABLgAECn82AAIKAAkJMyLGCwDsAgAKAAkJMyLGCwDsAgAAAA==.Magekaestey:BAABLgAECn8bAAIeAAkJ4BasSADmAQAeAAkJ4BasSADmAQAAAA==.Majandra:BAAALgAECgQJBwAAAA==.Malyndra:BAABLgAECn8iAAIQAAkJ1xeIDgAHAgAQAAkJ1xeIDgAHAgAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAAALgAECggJCAAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgADCgMJAwAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQANAAAAAA==.Meriam:BAAALgAECgEJAgABLgAECgkJKQAFANUeAA==.Merlot:BAAALgADCgEJAgABLgAECgQJBgANAAAAAA==.Mesmash:BAABLgAECn8gAAIgAAgJlxuiCwANAgAgAAgJlxuiCwANAgAAAA==.Metadk:BAAALgAECgMJAwABLgAECggJGQAUAGIXAA==.Metahunt:BAAALgAECgEJAQABLgAECggJGQAUAGIXAA==.Metamasters:BAAALgAECgQJBAABLgAECggJGQAUAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8mAAIJAAgJ+hnoEAAUAgAJAAgJ+hnoEAAUAgAAAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8gAAIEAAgJeBo7IQA3AgAEAAgJeBo7IQA3AgABLgAFFAQJDAAKAEIbAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAAALgAECggJEgAAAA==.Monkter:BAABLgAECn8ZAAQUAAgJYheVFgDYAQAUAAgJYheVFgDYAQATAAEJ/gbfbgAmAAAJAAEJfghsjQAiAAAAAA==.Moofasaha:BAAALgAECggJDwAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQAXAAceAA==.Morog:BAACLgAFFH8JAAMlAAQJEhX8DwAyAQAlAAQJEhX8DwAyAQAEAAEJ0w3QegBCAAAuAAQKfykABBIACQmpGyMsAM0BABIABgmOHSMsAM0BAAQABgkbGq0/ALABACUABgnqE1IkAFkBAAAA.Morragan:BAAALgAECgIJAgAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJBAABLgAECggJGQAUAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.',
Na='Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8NAAIDAAQJ6R+BAgB/AQADAAQJ6R+BAgB/AQAuAAQKf0AAAwMACAkQJo0BAA0DAAMACAkQJo0BAA0DAAcAAQmuAguKABsAAAAA.Nanarus:BAACLgAFFH8FAAIPAAIJfRmhHQCeAAAPAAIJfRmhHQCeAAAuAAQKfzUAAg8ACQm6HR8GAPQCAA8ACQm6HR8GAPQCAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAQAAAA==.Nashalie:BAABLgAECn8fAAIdAAkJhBpVJAA0AgAdAAkJhBpVJAA0AgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Nefele:BAABLgAECn8aAAIBAAgJ7xWYKADtAQABAAgJ7xWYKADtAQAAAA==.Nepheli:BAABLgAECn84AAIXAAkJCyAOCgDjAgAXAAkJCyAOCgDjAgAAAA==.Newrhu:BAAALgADCgcJCQAAAA==.Nexbasia:BAABLgAECn81AAMDAAkJWRAVDADCAQADAAkJWRAVDADCAQACAAIJ9gI73QAcAAAAAA==.',
Ni='Nickyboy:BAABLgAECn8kAAQcAAcJyiExBAAVAgAcAAcJyiExBAAVAgAdAAIJvg7q4ABuAAAkAAEJrBe1LwA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgEJAQAAAA==.Nikash:BAABLgAECn8lAAMHAAcJ2gyiNAAUAQAHAAcJ2gyiNAAUAQACAAYJ+Qh/cQDAAAAAAA==.Nisato:BAAALgAECgQJBAAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgADCgcJBwABLgAECggJNAAFANcgAA==.',
Ny='Nyriah:BAAALgAECgUJCgAAAA==.',
Ob='Obm:BAAALgAECgQJBAAAAA==.',
Oc='Octt:BAABLgAECn8bAAIdAAkJOxthKAAhAgAdAAkJOxthKAAhAgAAAA==.',
Of='Offal:BAABLgAECn8iAAQhAAYJZxAJGAA5AQAhAAYJCAsJGAA5AQAgAAYJZxD4IgDvAAAfAAEJJQWolAAmAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCAAAAA==.',
Om='Ominis:BAAALgAECgMJAwAAAA==.',
Oo='Oomaw:BAAALgAECgMJAwAAAA==.',
Or='Orcal:BAACLgAFFH8bAAIiAAUJXBTxHgAhAQAiAAUJXBTxHgAhAQAuAAQKfx0AAiIACAn7GnQQAHECACIACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAAALgAECgUJDwAAAA==.',
Ot='Otherrhu:BAAALgADCgYJBgAAAA==.',
Oz='Ozo:BAABLgAECn8cAAIEAAcJqBIxVgBzAQAEAAcJqBIxVgBzAQAAAA==.',
Pa='Paiva:BAAALgAECgQJBAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn81AAILAAkJ3iB0AwCzAgALAAkJ3iB0AwCzAgAAAA==.Pampas:BAABLgAECn8VAAMBAAcJRQQWbADdAAABAAcJRQQWbADdAAARAAEJRAFOngAaAAAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgQJBAAAAA==.Phoebell:BAAALgAECgMJBgAAAA==.',
Pi='Pinkducky:BAABLgAECn8cAAIFAAYJyQXCzgC8AAAFAAYJyQXCzgC8AAAAAA==.',
Pl='Plen:BAABLgAECn8pAAMFAAkJ1R5aNQBhAgAFAAkJkxxaNQBhAgAYAAYJwhtZFQCSAQAAAA==.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgIJAgAAAA==.Poquads:BAAALgADCgkJGQAAAA==.',
Pr='Primaris:BAAALgAECgUJCgAAAA==.Príestatute:BAAALgADCggJCAABLgAECgkJKwAEAKUaAA==.',
Pu='Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJLAAOAG4PAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIeAAkJmBi/NAAoAgAeAAkJmBi/NAAoAgAAAA==.',
Ra='Radra:BAAALgAECgUJCwAAAA==.Raeku:BAABLgAECn8lAAIlAAkJgSAAAwAFAwAlAAkJgSAAAwAFAwAAAA==.Rainee:BAAALgADCgEJAQAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgEJAQAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMMAAYJhRXxEwDlAAAXAAYJnBOKbQAiAQAMAAUJPxXxEwDlAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJghBagDjAAABAAcJtgRBagDjAAARAAYJUQPIXQCaAAAAAA==.Retribution:BAABLgAECn8uAAIKAAkJxhAFQwDeAQAKAAkJxhAFQwDeAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgIJAwABLgAECggJOQAUAJIjAA==.',
Ro='Robomurph:BAAALgADCggJDwAAAA==.Ronfax:BAACLgAFFH8aAAMBAAYJPCIJAgB0AgABAAYJPCIJAgB0AgARAAEJ6QOHIABAAAAuAAQKfx0AAwEACQmcI8gFADADAAEACQmcI8gFADADABEAAQl1F66GADMAAAAA.Rooss:BAAALgAECgYJEAAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECggJEQAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAUAGIXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.Rul:BAAALgAECgQJBQABLgAFFAQJDwAFAJ4gAA==.',
Ry='Ryllae:BAAALgAECgMJAwABLgAECgkJFgAQANgbAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Saint:BAAALgAECgYJBQAAAA==.Samson:BAAALgAECgUJDAABLgAECgQJBAANAAAAAA==.Sanivan:BAABLgAECn8VAAIQAAcJ+hdxGgDvAQAQAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Sappy:BAABLgAECn8ZAAQbAAcJdR9BCQCuAQAbAAYJAx5BCQCuAQAjAAQJrxwzOwA/AQAmAAQJ8BLcCQDFAAABLgAFFAQJDwAFAJ4gAA==.Sarinae:BAABLgAECn8ZAAQiAAgJzAQkUQC/AAAiAAcJsQMkUQC/AAAnAAEJwAH7OgAfAAAZAAEJwAFIJQAXAAAAAA==.Sarmuc:BAABLgAECn8UAAMVAAgJjg7wFAArAQAVAAgJjg7wFAArAQARAAEJXwsqjwAqAAAAAA==.Saryda:BAAALgAECgQJBgAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJCwABLgAECgkJKQAFANUeAA==.Scubagal:BAAALgAECgMJBgAAAA==.Scy:BAAALgAECgQJAQAAAA==.Scythraza:BAABLgAECn8VAAMiAAgJSQ7yLABiAQAiAAgJSQ7yLABiAQAnAAEJCQRaNgArAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJLAAOAG4PAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8XAAIXAAYJvBzvTwBzAQAXAAYJvBzvTwBzAQAAAA==.Sensu:BAAALgAECgUJCwAAAA==.Sensual:BAAALgAECgMJAwAAAA==.Sernian:BAAALgAECgQJCAABLgAFFAQJEAAKAIEiAA==.Seä:BAABLgAECn8sAAIOAAkJbg+PIwDCAQAOAAkJbg+PIwDCAQAAAA==.',
Sh='Shadoweave:BAABLgAECn8XAAIWAAkJ1wb3LABHAQAWAAkJ1wb3LABHAQAAAA==.Shamtea:BAABLgAECn8lAAIRAAgJLgqMNwApAQARAAgJLgqMNwApAQAAAA==.Shapzan:BAAALgAECgQJCwAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shivant:BAABLgAECn8kAAMBAAgJ2R3OGABWAgABAAgJ2R3OGABWAgARAAEJ9gKCnQAcAAAAAA==.Shmeegleroop:BAAALgADCgQJBAAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAABLgAECn8dAAIMAAkJ3ByZBABKAgAMAAkJ3ByZBABKAgAAAA==.',
Si='Sindice:BAAALgAECgYJBwABLgAFFAYJGgABADwiAA==.',
Sk='Skaa:BAAALgAECgEJAQAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slimpooshady:BAABLgAECn8aAAICAAkJFhJzIgASAgACAAkJFhJzIgASAgAAAA==.',
So='Solaspirus:BAABLgAECn8gAAMXAAgJJBfuNQDOAQAXAAgJJBfuNQDOAQAMAAEJawzMKwAwAAAAAA==.Solinius:BAAALgAECgEJAQAAAA==.Sope:BAAALgAECgYJBwAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAABLgAECn8YAAIdAAcJ5wMcpwDbAAAdAAcJ5wMcpwDbAAAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIOAAgJPxwDDgCOAgAOAAgJPxwDDgCOAgAAAA==.Sprayinnseed:BAAALgAECgEJAQAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwANAAAAAA==.',
St='Stabon:BAABLgAECn8iAAIjAAgJvAk/IABnAQAjAAgJvAk/IABnAQAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgQJCgAAAA==.',
Sw='Sweetstorm:BAABLgAECn8pAAIQAAgJNgZeJwAEAQAQAAgJNgZeJwAEAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn8tAAIOAAkJWxcnEAB0AgAOAAkJWxcnEAB0AgAAAA==.',
Ta='Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAAALgAECgcJEQAAAA==.Tarixx:BAABLgAFFH8GAAMKAAMJ/w5hJACjAAAKAAIJQg5hJACjAAALAAEJeRBlEgA0AAAAAA==.Tazanoth:BAACLgAFFH8IAAQEAAMJBBI4TQDEAAAEAAMJ0Q84TQDEAAAlAAIJKQ76IACWAAASAAEJTArEJgBPAAAuAAQKfyEAAyUACQmaG5sLAE4CACUACQmQGpsLAE4CABIABglBGtYwALABAAAA.',
Te='Teasa:BAABLgAECn8yAAIEAAgJ1BSkNgDYAQAEAAgJ1BSkNgDYAQAAAA==.Tekeelà:BAACLgAFFH8JAAQEAAUJwwdDAgB7AQAEAAUJwwdDAgB7AQAlAAEJhAF8KwA1AAASAAEJVgAiLgA1AAAuAAQKfy8ABAQACQn/IKMVAIoCAAQACAkfIKMVAIoCACUACQm6GOwLAEkCABIABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAAALgAECgUJDQAAAA==.Theenna:BAAALgADCgUJBQAAAA==.Thetodd:BAAALgADCgUJBQAAAA==.Thianna:BAABLgAECn8dAAMOAAkJlBYdGgANAgAOAAkJlBYdGgANAgAKAAYJ8QptvADqAAAAAA==.Thiculuskage:BAABLgAECn8WAAIOAAgJLB6gCwCvAgAOAAgJLB6gCwCvAgAAAA==.Thinkso:BAAALgADCgcJFQAAAA==.Thobu:BAAALgAECgYJCQAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn85AAQiAAkJ1howEABHAgAiAAkJ1howEABHAgAZAAUJvBZUCwBAAQAnAAYJogvrKAAsAQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgUJBwABLgAECgkJKwAEAKUaAA==.Timeforloads:BAABLgAECn8WAAMCAAcJtx3bPQB5AQACAAYJSxzbPQB5AQAHAAMJ6g7JXwBkAAAAAA==.',
To='Tolk:BAAALgAECgYJDgAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAAALgAECggJEgAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Troloq:BAABLgAECn80AAQkAAkJWB3vBQDwAQAdAAgJHhsSLgAIAgAkAAgJHRfvBQDwAQAcAAUJ8BnjDwAXAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgADCgcJEgAAAA==.Turger:BAAALgAECgQJBQABLgAECggJDwANAAAAAA==.',
Ul='Uller:BAABLgAECn8gAAIeAAgJNhnfSQDiAQAeAAgJNhnfSQDiAQAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAAALgAECgUJEAAAAA==.Vaimei:BAABLgAECn8vAAMcAAkJaSLQAQCWAgAcAAgJyiLQAQCWAgAdAAgJtx6KFgCGAgAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Vapor:BAABLgAECn8dAAIbAAcJ+BX0CACRAQAbAAcJ+BX0CACRAQAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebs:BAAALgAECgYJDQAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8dAAIeAAgJYAY1kQA6AQAeAAgJYAY1kQA6AQAAAA==.Vento:BAABLgAECn8VAAIFAAgJjxUZTwCyAQAFAAgJjxUZTwCyAQAAAA==.Verité:BAAALgAECgYJCwAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAECggJOAAKAMohAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn8xAAIXAAkJuBL3OgC6AQAXAAkJuBL3OgC6AQAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAECgkJJwABAAAYAA==.',
Vv='Vvicked:BAABLgAECn8eAAIFAAcJ8SBOKQA5AgAFAAcJ8SBOKQA5AgAAAA==.',
Vy='Vynesta:BAABLgAECn8WAAIQAAkJ2BtBCQBpAgAQAAkJ2BtBCQBpAgAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wanagi:BAAALgADCgMJAwAAAA==.Wankz:BAAALgAECggJEAAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8dAAIfAAgJSiJ+DAB/AgAfAAgJSiJ+DAB/AgAAAA==.',
We='Weyna:BAABLgAECn8wAAMTAAgJsQ0oMgBdAQATAAgJsQ0oMgBdAQAJAAYJVAnVQwDPAAABLgAFFAQJFQAnAGYWAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.',
Wi='Widowx:BAABLgAECn8rAAIRAAkJPBinFwD7AQARAAkJPBinFwD7AQAAAA==.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAAALgAECgcJDgABLgAECggJKwAPABMiAA==.',
Wr='Wrandohunt:BAAALgAECgEJAwAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgADCgQJBAAAAA==.Wryn:BAAALgAECgcJDwABLgAECgkJKQAFANUeAA==.',
Wu='Wulyn:BAAALgAECgUJCwAAAA==.',
Wy='Wylla:BAAALgAECgQJBgAAAA==.',
Xa='Xalethra:BAABLgAECn80AAIXAAkJBySKAwA+AwAXAAkJBySKAwA+AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xenophobias:BAAALgAECgYJEAAAAA==.',
Xh='Xhosen:BAAALgAECgQJDQAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn82AAICAAkJRBeAIQAZAgACAAkJRBeAIQAZAgAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zalajin:BAAALgAECgQJBAAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zarayndia:BAAALgAECgQJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8dAAMkAAgJBQUWFQDkAAAkAAcJAgUWFQDkAAAdAAUJ0ANE0wCKAAAAAA==.Zendragan:BAABLgAECn8dAAITAAgJtRhZGAAXAgATAAgJtRhZGAAXAgAAAA==.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.',
Zz='Zzilladi:BAAALgAFFAMJBAAAAA==.Zzilladinzz:BAACLgAFFH8TAAIKAAQJjSBaGQBtAQAKAAQJjSBaGQBtAQAuAAQKfyIAAgoACQkIIwsSAAIDAAoACQkIIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgYJDwABLgAECgkJHQAMANwcAA==.',
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
