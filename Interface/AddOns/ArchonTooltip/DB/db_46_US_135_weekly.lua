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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Frost','Rogue-Subtlety','Paladin-Protection','Priest-Holy','DemonHunter-Vengeance','Rogue-Outlaw','Warlock-Affliction','Druid-Balance','Hunter-Survival','Warrior-Arms','Paladin-Holy','Warrior-Fury','Shaman-Enhancement','Warrior-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Acallia:BAAALgAECgQJCwAAAA==.Achkmed:BAABLgAECn8bAAIBAAcJfhjDhABjAQABAAcJfhjDhABjAQAAAA==.',
Ae='Aelynis:BAABLgAECn8mAAICAAkJOw+VCADFAQACAAkJOw+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+glPSgAHAQADAAgJ+glPSgAHAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGgfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgQJDwAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.Amberina:BAAALgADCgkJEgAAAA==.',
An='Annerose:BAABLgAECn8qAAIFAAgJgwTGrgDFAAAFAAgJgwTGrgDFAAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn9FAAMEAAkJFR1SHgCkAgAEAAkJFR1SHgCkAgAGAAEJiAOgFQAlAAAAAA==.',
Ap='Apollo:BAAALgAFFAEJAgAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgAECgIJAgAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Arette:BAAALgADCgEJAQABLgAECgcJGAAIAHUDAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgMJAwAAAA==.Arioriaa:BAABLgAECn8uAAIKAAgJ8gxTTwBwAQAKAAgJ8gxTTwBwAQAAAA==.Arlind:BAAALgAECgYJEQAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.Asslind:BAAALgADCgUJBQAAAA==.Assuutu:BAAALgADCgMJAwAAAA==.',
At='Atanatari:BAAALgAECgEJAQABLgAECgYJEwALAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azarine:BAAALgADCggJCQAAAA==.Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgMJAwAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAABLgAECn8lAAIBAAkJ1hgWMAA+AgABAAkJ1hgWMAA+AgAAAA==.Battleares:BAAALgAECgYJEAAAAA==.',
Be='Beardalorian:BAAALgAECgUJBgAAAA==.Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8yAAIMAAcJWA3oEwAMAQAMAAcJWA3oEwAMAQAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Bigstan:BAAALgAECgcJDwAAAA==.Bilbobagging:BAAALgAECgMJBAABLgAFFAYJCwAEAGoVAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgYJDwAAAA==.',
Bl='Blackendmoon:BAAALgAECgQJCgAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAECgIJBQAAAA==.Bluebeary:BAAALgAECgQJBwAAAA==.Bluebubbles:BAAALgADCgkJCQAAAA==.Bluelocks:BAACLgAFFH8GAAIMAAQJRgGxEQCmAAAMAAQJRgGxEQCmAAAuAAQKfywAAwwACAmNEIoNAGABAAwACAmNEIoNAGABAA0AAQlOAuBZASQAAAAA.Blufoot:BAAALgAECgUJBQAAAA==.Bluéyes:BAAALgAECgUJCQAAAA==.Blvckscvl:BAABLgAECn8hAAMOAAgJvBzsFgCBAgAOAAgJvBzsFgCBAgAPAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgYJCQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.Borrne:BAAALgAECgEJAQAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.Brujha:BAAALgAECgYJDAABLgAFFAMJBQAFABkEAA==.',
Bu='Burnttoast:BAAALgADCgMJAwABLgAECgkJGwABAH4YAA==.',
Ca='Caledra:BAAALgAECgEJAQAAAA==.Calinai:BAAALgAECgIJAgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8xAAIQAAgJABOYZACbAQAQAAgJABOYZACbAQAAAA==.',
Ce='Cellturin:BAAALgAECgkJEQAAAA==.',
Ch='Chelais:BAAALgAECgQJBAABLgABCgMJAwALAAAAAA==.Chiarakai:BAAALgADCgkJHgAAAA==.Chobits:BAAALgAECgUJBgAAAA==.Choc:BAAALgADCgMJAwAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Corvany:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Creeder:BAABLgAECn8jAAIBAAkJuRADdACTAQABAAkJuRADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.Darthmeep:BAAALgAECgIJBAABLgAECgcJEAALAAAAAA==.',
De='Deaanor:BAABLgAECn8dAAIRAAcJvQdpNwDYAAARAAcJvQdpNwDYAAAAAA==.Deathcòw:BAACLgAFFH8HAAIQAAMJgh0eaQAmAQAQAAMJgh0eaQAmAQAuAAQKfzwAAxAACQnWIyoLABMDABAACQnWIyoLABMDABIAAgmaCQg+AFkAAAAA.Deathpanthr:BAAALgAECgEJAQABLgAECgYJBgALAAAAAA==.Demonhunter:BAAALgAECgIJAgAAAA==.Demonia:BAAALgADCgYJBgAAAA==.Detective:BAABLgAECn8XAAITAAkJFQvTOgBdAQATAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJGQAAAA==.Dilligafehno:BAAALgADCgkJEgAAAA==.Dionysuz:BAAALgADCgMJAwAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn84AAITAAkJ/xoJDABzAgATAAkJ/xoJDABzAgAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgAECgUJBQABLgAECgkJGwABAH4YAA==.',
Dr='Draann:BAAALgADCggJBwABLgAECgQJBwALAAAAAA==.Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Drdeer:BAABLgAECn8nAAIUAAkJGRS2IwAqAgAUAAkJGRS2IwAqAgAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgMJAwAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ec='Ecclesiarchy:BAAALgADCgkJEQAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAABLgAFFH8IAAMVAAMJ7w0+JgC0AAAVAAMJyg0+JgC0AAATAAEJxAk2WwA2AAAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgQJBQAAAA==.Ethidris:BAAALgADCgkJEgABLgAECgkJGwABAH4YAA==.',
Ev='Evang:BAABLgAECn8sAAIOAAgJdBRUQwDTAQAOAAgJdBRUQwDTAQAAAA==.Eve:BAAALgAFFAMJBAABLgAFFAYJCgABAFwaAA==.Everd:BAABLgAECn8+AAIBAAkJOhYgOAAfAgABAAkJOhYgOAAfAgAAAA==.Evren:BAABLgAFFH8GAAIWAAMJPxRkOQC1AAAWAAMJPxRkOQC1AAAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgMJAwAAAA==.Feârless:BAAALgAECgYJBgAAAA==.',
Fi='Fiametta:BAABLgAECn9HAAIMAAkJ4yHcAAALAwAMAAkJ4yHcAAALAwAAAA==.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flameward:BAAALgAECgQJBAAAAA==.Flent:BAABLgAECn8bAAMPAAgJKguKEwAjAQAPAAgJKguKEwAjAQAOAAEJqQatOwEuAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwALAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fr='Frostydck:BAAALgAECgEJAgAAAA==.',
Fu='Funsize:BAAALgAECgUJCgAAAA==.',
Ga='Gabagoop:BAAALgAECggJEwAAAA==.Galindlianid:BAABLgAECn8jAAIBAAkJAARwxAD/AAABAAkJAARwxAD/AAAAAA==.Gazzlok:BAAALgAECgMJAwAAAA==.',
Ge='Gernik:BAAALgAECgEJAQAAAA==.Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgIJBAAAAA==.',
Gh='Ghuldan:BAAALgAECgEJAQAAAA==.',
Gi='Gigaweenie:BAAALgAFFAIJBAAAAA==.',
Gl='Glavien:BAABLgAECn83AAIBAAkJxA7xaACbAQABAAkJxA7xaACbAQAAAA==.Global:BAAALgADCgkJCQABLgAECggJKgAGAE4dAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.',
Gr='Grandstorm:BAAALgADCgQJBAAAAA==.Greg:BAAALgADCgYJCAAAAA==.Grienke:BAAALgADCgQJBAABLgAECgkJMgAXADMgAA==.Grumpolbolt:BAABLgAECn8eAAIYAAgJ9RkuJwC/AQAYAAgJ9RkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgQJBQAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQAMAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hellmet:BAAALgAECgcJCQAAAA==.Hey:BAACLgAFFH8KAAIKAAMJaB5YNwD9AAAKAAMJaB5YNwD9AAAuAAQKf1EAAgoACQknIk4GAEkDAAoACQknIk4GAEkDAAAA.',
Hi='Hidatix:BAAALgADCgEJAQAAAA==.Hinamori:BAAALgAECggJDAAAAA==.',
Ho='Homble:BAAALgADCgQJBAAAAA==.Horadin:BAAALgAECgMJAwAAAA==.Horneswaggle:BAAALgAECgEJAQAAAA==.',
Hu='Huntmeister:BAABLgAECn8qAAIOAAgJtyEEDQDWAgAOAAgJtyEEDQDWAgAAAA==.Huogmi:BAAALgAECgYJCAAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAIQAAgJuiKrIgB6AgAQAAgJuiKrIgB6AgAAAA==.',
Il='Ilharra:BAABLgAECn8aAAMIAAUJ5Q0UUgDGAAAIAAUJ5Q0UUgDGAAAJAAUJsgJMWgCRAAAAAA==.Ilililili:BAAALgAECgQJCAAAAA==.Illee:BAAALgAECgcJEgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAFFAMJCAASAFEgAA==.Imturtle:BAACLgAFFH8IAAMSAAMJUSDPGQATAQASAAMJUSDPGQATAQAQAAEJLBPgDAE/AAAuAAQKf0YAAxIACQlwI80CABoDABIACQlwI80CABoDABAABwn/FKKrABcBAAAA.',
In='Insømniadk:BAABLgAFFH8JAAIQAAMJwiDHigDwAAAQAAMJwiDHigDwAAABLgAFFAYJHAAQAOkgAA==.',
Is='Isshiny:BAABLgAECn8ZAAIBAAgJGxk3TQDdAQABAAgJGxk3TQDdAQAAAA==.Isweat:BAAALgAECgMJAwABLgAECgQJBQALAAAAAA==.',
Iu='Iupiter:BAABLgAECn8UAAIBAAgJTBWSawCVAQABAAgJTBWSawCVAQAAAA==.',
Iv='Ivelos:BAAALgADCgIJAwAAAA==.',
Iy='Iyahlieairia:BAAALgAECgUJBQAAAA==.',
Iz='Izabeth:BAABLgAECn8gAAIEAAkJNQ03ZQCwAQAEAAkJNQ03ZQCwAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAABLgAECn8uAAIZAAgJhA98FwBhAQAZAAgJhA98FwBhAQAAAA==.',
Je='Jessabella:BAAALgADCgQJBAAAAA==.Jesyikaxyz:BAAALgAECgkJCgAAAA==.',
Ji='Jifycornbred:BAAALgAECgMJAwAAAA==.Jigles:BAAALgAECgEJAQAAAA==.',
['Jä']='Jägermeister:BAAALgAECgIJBAABLgAECgUJBQALAAAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kalypso:BAAALgADCgkJCQABLgAECgkJPAAJAA0aAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8gAAIKAAkJzQV4XwAOAQAKAAkJzQV4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgAECgUJBgAAAA==.',
Ki='Kialla:BAAALgADCgYJCQABLgAECgkJGwABAH4YAA==.Kiraneem:BAABLgAECn81AAMOAAkJVR71EwCuAgAOAAkJVR71EwCuAgAPAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn9MAAMKAAkJ6BdvGACDAgAKAAkJ6BdvGACDAgADAAQJZgx5dACKAAAAAA==.',
Ko='Kongfupanda:BAAALgAECgYJBgAAAA==.Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8XAAIEAAgJchCWgwBtAQAEAAgJchCWgwBtAQAAAA==.Krinj:BAABLgAECn8oAAIQAAkJZh3SRgDrAQAQAAkJZh3SRgDrAQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgAECgQJBAAAAA==.',
Ky='Kyarla:BAABLgAECn8kAAIaAAUJ6hUtOAAWAQAaAAUJ6hUtOAAWAQAAAA==.Kydo:BAACLgAFFH8HAAIEAAMJfQlThwDQAAAEAAMJfQlThwDQAAAuAAQKfyYAAgQABwm9GHxmAK0BAAQABwm9GHxmAK0BAAAA.Kythera:BAAALgAECgQJBwAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn8+AAMIAAkJMxc8EgBCAgAIAAkJMxc8EgBCAgAaAAEJpQqLdwAgAAAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECgkJMgAXADMgAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9bAAIYAAkJoR61CQCGAgAYAAkJoR61CQCGAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgQJCAAAAA==.Lovécoil:BAAALgAECgEJAgAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn88AAIJAAkJDRqmCwCyAgAJAAkJDRqmCwCyAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8kAAQFAAkJGBmrLwAFAgAFAAkJlxarLwAFAgARAAMJ7BHqQQCqAAAbAAEJZw7JMwAyAAAAAA==.',
['Lë']='Lëw:BAAALgAFFAEJAQAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQALAAAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAABLgAECn8ZAAIcAAgJLwrdDABDAQAcAAgJLwrdDABDAQAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8gAAIaAAkJBR8DCwCzAgAaAAkJBR8DCwCzAgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECggJEgAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAACLgAFFH8FAAMdAAMJVRkhGwBVAAANAAIJhRePjQCiAAAdAAEJ8xwhGwBVAAAuAAQKfx0AAw0ACQl4JYw4ACkCAA0ABwnEJYw4ACkCAAwAAwm6InEnACYBAAAA.',
Me='Medreaux:BAABLgAECn9NAAIaAAkJuhxBCgDAAgAaAAkJuhxBCgDAAgAAAA==.Metalknyte:BAABLgAECn81AAISAAkJZRTSEQDtAQASAAkJZRTSEQDtAQAAAA==.',
Mi='Miniknyte:BAABLgAECn8oAAMUAAkJnQxPSgBjAQAUAAkJnQxPSgBjAQAeAAEJvQ81iQA1AAAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiCPCgASAgAHAAcJiiCPCgASAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mogden:BAAALgAFFAEJAQABLgAECgkJIAAFAIIgAA==.Mohu:BAAALgADCgYJBgAAAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJSwAAAA==.Morghulis:BAAALgAECgUJBQAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.Mukakin:BAAALgADCgEJAQAAAA==.',
My='Mychelle:BAABLgAECn8/AAMfAAkJ+hkrCgB7AgAfAAkJXBgrCgB7AgAPAAgJ3hWaCwCpAQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn85AAIEAAkJMQlaeQCCAQAEAAkJMQlaeQCCAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgUJDAALAAAAAA==.Nezaeth:BAAALgAECgUJDAAAAA==.Nezum:BAAALgADCggJEAABLgAECgUJDAALAAAAAA==.',
Ni='Nickoli:BAAALgAECgUJBgAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgMJAwAAAA==.Nojomoto:BAAALgAECgIJBAAAAA==.Norabel:BAAALgAECgYJDQAAAA==.',
Ny='Nyra:BAABLgAECn8qAAIOAAkJ6B4lEgC8AgAOAAkJ6B4lEgC8AgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn9GAAMMAAkJ7x52AQDPAgAMAAkJ7x52AQDPAgANAAYJ2AsIqADxAAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8fAAMeAAkJ2B5rEABZAgAeAAkJ2B5rEABZAgAUAAcJLQ4qXwA0AQABLgAFFAMJBQAEAEAEAA==.',
Ol='Oldben:BAABLgAFFH8KAAIBAAQJPQpSUwADAQABAAQJPQpSUwADAQAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAgJJAAgAJAfAA==.Oriel:BAABLgAECn81AAIJAAkJIw2qIADGAQAJAAkJIw2qIADGAQAAAA==.Orthein:BAAALgAECgQJBgABLgAECgcJEAALAAAAAA==.',
Pa='Paleblueeye:BAAALgAECgEJAgAAAA==.Paragas:BAAALgAECgYJBgAAAA==.Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgQJBAAAAA==.',
Ph='Phindin:BAABLgAECn8/AAMDAAkJcRR4HwDjAQADAAkJcRR4HwDjAQAKAAcJxwWbeQDtAAAAAA==.',
Pi='Pixystix:BAAALgADCgkJCQABLgAECgkJPwAfAPoZAA==.',
Po='Poc:BAABLgAECn8lAAIHAAgJ3BHmEwB8AQAHAAgJ3BHmEwB8AQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgAECgkJEQAAAA==.Primo:BAAALgAECgYJDAAAAA==.Prinsana:BAABLgAECn81AAIZAAkJPBUfDQDvAQAZAAkJPBUfDQDvAQAAAA==.',
Pu='Puddytat:BAAALgADCgMJAwAAAA==.Purged:BAABLgAECn8gAAIKAAkJOAZRXgA8AQAKAAkJOAZRXgA8AQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Py='Pya:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Raidwipe:BAAALgADCgIJAgABLgAECgcJEAALAAAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgABLgAECgUJBQALAAAAAA==.Ratheer:BAABLgAFFH8FAAIFAAIJSRWpeQCEAAAFAAIJSRWpeQCEAAABLgAFFAMJBQAdAFUZAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8uAAIhAAgJyRw+EACUAgAhAAgJyRw+EACUAgAAAA==.',
Rh='Rhoana:BAAALgADCgcJBwAAAA==.',
Rl='Rllybuffnerd:BAAALgAECgIJAgAAAA==.',
Ro='Rodikus:BAACLgAFFH8KAAIaAAQJkRh5EgAxAQAaAAQJkRh5EgAxAQAuAAQKfz8AAxoACQlIIikRAFYCABoACAldIikRAFYCAAgACQkrFqgVAB4CAAAA.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8jAAIFAAgJxRlVNgDqAQAFAAgJxRlVNgDqAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAVAJwPAA==.',
Ru='Rukus:BAAALgADCgQJBAAAAA==.',
['Rä']='Räwry:BAAALgAFFAQJBAABLgAFFAMJCAAJAAoMAA==.',
Sa='Saiaa:BAABLgAECn8aAAICAAkJYQV3DgA6AQACAAkJYQV3DgA6AQAAAA==.Sakeena:BAAALgAECgQJCAAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAABLgAECn8YAAIIAAcJdQNSWgCoAAAIAAcJdQNSWgCoAAAAAA==.Sattia:BAABLgAECn9LAAIUAAkJOgdoWgAmAQAUAAkJOgdoWgAmAQAAAA==.',
Sc='Scampington:BAAALgAECgYJCwAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhgWGwAuAQAHAAYJXhgWGwAuAQAAAA==.',
Sh='Sharokk:BAAALgAECgcJCQABLgAECggJIwAFAMUZAA==.Sharrow:BAAALgAECgMJAwAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8uAAMTAAgJDBMGJwB1AQATAAgJZxEGJwB1AQAVAAEJ1xQSjwA/AAAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn81AAIiAAkJUBxgEAB0AgAiAAkJUBxgEAB0AgAAAA==.Simphunter:BAEBLgAECn83AAIFAAkJfB7VEAC5AgAFAAkJfB7VEAC5AgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn85AAIRAAkJAxDvGAC2AQARAAkJAxDvGAC2AQAAAA==.Sit:BAAALgAECggJEQAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgiC/GQC6AgAFAAkJgiC/GQC6AgAAAA==.',
Sl='Slït:BAAALgADCgIJAgAAAA==.',
Sm='Smellme:BAAALgAECgMJAwAAAA==.Smitedaddy:BAAALgAECgEJAQAAAA==.Smothbran:BAAALgADCgIJAwAAAA==.',
Sn='Snapdragon:BAAALgAECgQJBgAAAA==.',
So='Solarasun:BAAALgADCgkJDgABLgAECgYJEwALAAAAAA==.Soluna:BAAALgAECgQJBAAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgQJCAAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwATABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn8tAAIPAAkJDBiYBQBDAgAPAAkJDBiYBQBDAgAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgQJBQAAAA==.Stillwing:BAAALgADCgIJAgAAAA==.Stormkraa:BAAALgAECgkJBwAAAA==.Strawyà:BAAALgADCgQJBwABLgAECgkJOgAZANAbAA==.Strawyæ:BAABLgAECn86AAIZAAkJ0Bs4CABSAgAZAAkJ0Bs4CABSAgAAAA==.Strike:BAAALgAECgYJCAABLgAFFAYJEwAhAHARAA==.',
Su='Succubi:BAAALgADCgIJAgAAAA==.Sugerfree:BAAALgAECgYJDAAAAA==.Sulkra:BAAALgAECgcJAQAAAA==.Suttercane:BAAALgAECgYJCQAAAA==.',
['Sì']='Sìrocco:BAAALgAECgYJCwAAAA==.',
Ta='Taleranor:BAAALgAECgcJEwAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8sAAMfAAkJhRMPEwAPAgAfAAkJZxEPEwAPAgAPAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgYJCAAAAA==.Teekeez:BAABLgAECn8bAAIEAAgJmQh7wgACAQAEAAgJmQh7wgACAQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgAECgIJBAAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn8/AAIiAAkJhxtEDQCXAgAiAAkJhxtEDQCXAgAAAA==.Thorek:BAAALgADCgkJGQAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.Thunderracks:BAAALgAECgEJAQAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAABLgAFFAYJCwAEAGoVAA==.Tralle:BAAALgAECgMJAwAAAA==.Trapology:BAAALgAECgEJBAAAAA==.Trisky:BAABLgAECn8rAAMhAAkJ1BjpHAAZAgAhAAgJjxfpHAAZAgABAAcJNQ57nwA2AQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwALAAAAAA==.Trydént:BAAALgAECgQJCAAAAA==.Trystàn:BAAALgADCgUJBQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAABLgAECn8dAAMNAAYJzhp4WgCNAQANAAYJzhp4WgCNAQAMAAIJmwYhRAAiAAABLgAFFAMJCAASAFEgAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Un='Unhenged:BAAALgADCgQJBAAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8sAAIjAAkJCyFlBgBwAgAjAAkJCyFlBgBwAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.Vantadim:BAAALgADCgUJBQAAAA==.',
Ve='Vegito:BAABLgAECn8zAAIiAAgJfAUPTwALAQAiAAgJfAUPTwALAQAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgAECgMJBAAAAA==.Vistus:BAAALgAECgcJCwAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECgkJPwAfAPoZAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RIImADsAAAFAAYJ+RIImADsAAABLgAECggJKgAOALchAA==.Voin:BAACLgAFFH8FAAIkAAUJERnrDgA5AQAkAAUJERnrDgA5AQAuAAQKf2IAAyQACQnUJFkBAEoDACQACQnUJFkBAEoDACIABAl9G69TAPwAAAAA.Vorpine:BAABLgAECn8zAAMIAAkJQBdOHgDnAQAIAAcJkBlOHgDnAQAJAAkJpAymIQC/AQAAAA==.',
Vs='Vs:BAACLgAFFH8HAAIQAAMJ3RJHJQABAQAQAAMJ3RJHJQABAQAuAAQKfxUAAhAACAnYIKhSAPoBABAACAnYIKhSAPoBAAEuAAUUCQk/AAUAByUA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8cAAMWAAgJZxadJQDxAQAWAAgJZxadJQDxAQAVAAEJHgbvswAhAAAAAA==.',
Wi='Winterberrie:BAAALgADCgYJBAAAAA==.Wirhl:BAABLgAECn8dAAIOAAcJGxChdQBQAQAOAAcJGxChdQBQAQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8PAAIBAAUJQyBcKABjAQABAAUJQyBcKABjAQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB8MNAAuAgABAAgJRB8MNAAuAgAAAA==.',
Xa='Xalbit:BAABLgAECn80AAIKAAkJWR44CgAOAwAKAAkJWR44CgAOAwAAAA==.Xanae:BAAALgAECggJDgAAAA==.Xanthrash:BAAALgAECgcJEAAAAA==.Xantia:BAABLgAECn86AAIUAAkJaRaxHgBOAgAUAAkJaRaxHgBOAgAAAA==.Xaraena:BAABLgAECn8fAAIOAAkJfRr2KAATAgAOAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBgAAAA==.Xenlo:BAAALgAECgcJDwABLgAFFAUJFQAhAOQbAA==.',
Xy='Xyndrome:BAAALgAFFAEJAQAAAA==.Xyndrä:BAAALgADCgYJBgAAAA==.',
Yu='Yungun:BAAALgAECgEJAgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJGAAlAH8YAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwALAAAAAA==.',
Ze='Zeonhalifax:BAAALgAECgMJAwABLgAECgQJBQALAAAAAA==.Zercus:BAABLgAFFH8MAAIBAAQJXQmoVQD/AAABAAQJXQmoVQD/AAAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJCwAAAA==.',
['Ðr']='Ðread:BAABLgAECn8iAAMXAAgJog6lEABoAQAXAAgJUQ6lEABoAQAQAAYJEQwOwgD4AAAAAA==.',
['ßß']='ßßq:BAAALgAECgEJAQAAAA==.ßßqñüt:BAAALgAECgEJAQAAAA==.',
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
