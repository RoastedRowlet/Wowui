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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','DeathKnight-Frost','Rogue-Subtlety','Paladin-Protection','Priest-Holy','DemonHunter-Vengeance','Rogue-Outlaw','Warlock-Affliction','Hunter-Survival','Druid-Balance','Warrior-Arms','Paladin-Holy','Warrior-Fury','Shaman-Enhancement','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acallia:BAAALgAECgQJCwAAAA==.Achkmed:BAABLgAECn8YAAIBAAcJfhg2bQCjAQABAAcJfhg2bQCjAQAAAA==.',
Ae='Aelynis:BAABLgAECn8mAAICAAkJOw+VCADFAQACAAkJOw+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+gkeRwAHAQADAAgJ+gkeRwAHAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGgfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgQJDAAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.Amberina:BAAALgADCgkJCQAAAA==.',
An='Annerose:BAABLgAECn8oAAIFAAgJpgM4sAC5AAAFAAgJpgM4sAC5AAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn89AAMEAAkJDhqqLQBcAgAEAAkJDhqqLQBcAgAGAAEJiANcFAAlAAAAAA==.',
Ap='Apollo:BAAALgAFFAEJAQAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgAECgIJAgAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Arette:BAAALgADCgEJAQABLgAECgYJFgAIAKwCAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgMJAwAAAA==.Arioriaa:BAABLgAECn8sAAIKAAgJ1wvLUABgAQAKAAgJ1wvLUABgAQAAAA==.Arlind:BAAALgAECgUJDAAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.Assuutu:BAAALgADCgMJAwAAAA==.',
At='Atanatari:BAAALgAECgEJAQABLgAECgYJEAALAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azarine:BAAALgADCggJCQAAAA==.Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgMJAwAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAABLgAECn8lAAIBAAkJ1hhzLQBAAgABAAkJ1hhzLQBAAgAAAA==.Battleares:BAAALgAECgYJEAAAAA==.',
Be='Beardalorian:BAAALgAECgUJBgAAAA==.Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8sAAIMAAcJVwzvEwADAQAMAAcJVwzvEwADAQAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Bigstan:BAAALgAECgcJDwAAAA==.Bilbobagging:BAAALgAECgMJBAABLgAFFAYJCwAEAGoVAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgYJDwAAAA==.',
Bl='Blackendmoon:BAAALgAECgQJCgAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAECgIJBQAAAA==.Bluebeary:BAAALgAECgQJBAAAAA==.Bluelocks:BAACLgAFFH8GAAIMAAQJRgFQEACnAAAMAAQJRgFQEACnAAAuAAQKfysAAwwACAmNEKsMAGMBAAwACAmNEKsMAGMBAA0AAQlOAstPASQAAAAA.Bluéyes:BAAALgAECgQJBwAAAA==.Blvckscvl:BAABLgAECn8hAAMOAAgJvBzsFgCBAgAOAAgJvBzsFgCBAgAPAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgYJCQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.Borrne:BAAALgAECgEJAQAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.Brujha:BAAALgAECgYJDAABLgAECgkJOAAFABQaAA==.',
Bu='Burnttoast:BAAALgADCgMJAwABLgAECgkJGAABAH4YAA==.',
Ca='Caledra:BAAALgAECgEJAQAAAA==.Calinai:BAAALgAECgIJAgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8wAAIQAAgJABMFYQCeAQAQAAgJABMFYQCeAQAAAA==.',
Ce='Cellturin:BAAALgAECgkJEQAAAA==.',
Ch='Chelais:BAAALgAECgQJBAABLgABCgMJAwALAAAAAA==.Chiarakai:BAAALgADCgkJHgAAAA==.Chobits:BAAALgAECgUJBgAAAA==.Choc:BAAALgADCgMJAwAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Corvany:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Creeder:BAABLgAECn8jAAIBAAkJuRADdACTAQABAAkJuRADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.Darthmeep:BAAALgAECgIJAgAAAA==.',
De='Deaanor:BAABLgAECn8bAAIRAAcJageHNQDTAAARAAcJageHNQDTAAAAAA==.Deathcòw:BAACLgAFFH8GAAIQAAMJDBjtfQD4AAAQAAMJDBjtfQD4AAAuAAQKfzwAAxAACQnWIz8KABYDABAACQnWIz8KABYDABIAAgmaCQg+AFkAAAAA.Deathpanthr:BAAALgAECgEJAQABLgAECgIJAgALAAAAAA==.Demonhunter:BAAALgAECgIJAgAAAA==.Detective:BAABLgAECn8XAAITAAkJFQvTOgBdAQATAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJEAAAAA==.Dilligafehno:BAAALgADCgkJCQAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn8wAAITAAkJzBldDgBJAgATAAkJzBldDgBJAgAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgAECgUJBQABLgAECgkJGAABAH4YAA==.',
Dr='Draann:BAAALgADCggJBwABLgAECgQJBwALAAAAAA==.Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Drdeer:BAABLgAECn8fAAIUAAkJRRGALADtAQAUAAkJRRGALADtAQAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgMJAwAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ec='Ecclesiarchy:BAAALgADCgkJCQAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAABLgAFFH8FAAMVAAMJwQ3vKwCJAAAVAAIJwA/vKwCJAAATAAEJxAnwVwA2AAAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgQJBQAAAA==.Ethidris:BAAALgADCgQJBAABLgAECgkJGAABAH4YAA==.',
Ev='Evang:BAABLgAECn8qAAIOAAgJcxEcTgCsAQAOAAgJcxEcTgCsAQAAAA==.Eve:BAAALgAFFAMJBAABLgAFFAYJCgABAFwaAA==.Everd:BAABLgAECn84AAIBAAkJkxQSPgACAgABAAkJkxQSPgACAgAAAA==.Evren:BAAALgAFFAIJAwAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgMJAwAAAA==.Feârless:BAAALgAECgYJBgAAAA==.',
Fi='Fiametta:BAABLgAECn8/AAIMAAgJSyLPAQCvAgAMAAgJSyLPAQCvAgAAAA==.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flent:BAABLgAECn8bAAMPAAgJKgutEgAmAQAPAAgJKgutEgAmAQAOAAEJqQYtLwEuAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwALAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fu='Funsize:BAAALgAECgUJCgAAAA==.',
Ga='Gabagoop:BAAALgAECggJEAAAAA==.Galindlianid:BAABLgAECn8jAAIBAAkJAARLvAABAQABAAkJAARLvAABAQAAAA==.Gazzlok:BAAALgAECgIJAgAAAA==.',
Ge='Gernik:BAAALgAECgEJAQAAAA==.Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgIJBAAAAA==.',
Gh='Ghuldan:BAAALgAECgEJAQAAAA==.',
Gi='Gigaweenie:BAAALgAFFAIJBAAAAA==.',
Gl='Glavien:BAABLgAECn8xAAIBAAkJmA4XZwCWAQABAAkJmA4XZwCWAQAAAA==.Global:BAAALgADCgkJCQABLgAECgcJKQAGAFYfAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.',
Gr='Grandstorm:BAAALgADCgQJBAAAAA==.Greg:BAAALgADCgYJCAAAAA==.Grienke:BAAALgADCgQJBAABLgAECgkJMQAWADMgAA==.Grumpolbolt:BAABLgAECn8eAAIXAAgJ9RkuJwC/AQAXAAgJ9RkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgQJBQAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQAMAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hellmet:BAAALgAECgQJBgAAAA==.Hey:BAACLgAFFH8IAAIKAAIJphqOFQCsAAAKAAIJphqOFQCsAAAuAAQKf1EAAgoACQknIsUFAEsDAAoACQknIsUFAEsDAAAA.',
Hi='Hidatix:BAAALgADCgEJAQAAAA==.Hinamori:BAAALgAECggJCgAAAA==.',
Ho='Homble:BAAALgADCgQJBAAAAA==.Horadin:BAAALgAECgMJAwAAAA==.',
Hu='Huntmeister:BAABLgAECn8qAAIOAAgJtyEEDQDWAgAOAAgJtyEEDQDWAgAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAIQAAgJuiLXIAB9AgAQAAgJuiLXIAB9AgAAAA==.',
Il='Ilharra:BAABLgAECn8VAAMIAAUJ5Q0KTgDOAAAIAAUJ5Q0KTgDOAAAJAAUJsgL7VQCSAAAAAA==.Ilililili:BAAALgAECgQJBQAAAA==.Illee:BAAALgAECgcJEgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAFFAMJBwASAJkfAA==.Imturtle:BAACLgAFFH8HAAMSAAMJmR8vGAARAQASAAMJmR8vGAARAQAQAAEJLBOj+QBEAAAuAAQKf0YAAxIACQlwI5gCAB8DABIACQlwI5gCAB8DABAABwn/FLqmABkBAAAA.',
In='Insømniadk:BAABLgAFFH8JAAIQAAMJwiDCgADzAAAQAAMJwiDCgADzAAABLgAFFAYJHAAQAOkgAA==.',
Is='Isshiny:BAABLgAECn8ZAAIBAAgJGxmGSQDfAQABAAgJGxmGSQDfAQAAAA==.Isweat:BAAALgAECgMJAwABLgAECgQJBQALAAAAAA==.',
Iu='Iupiter:BAAALgAECgcJEwAAAA==.',
Iv='Ivelos:BAAALgADCgIJAwAAAA==.',
Iy='Iyahlieairia:BAAALgAECgUJBQAAAA==.',
Iz='Izabeth:BAABLgAECn8eAAIEAAgJPg2fdQCHAQAEAAgJPg2fdQCHAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAABLgAECn8sAAIYAAgJDA8lFwBaAQAYAAgJDA8lFwBaAQAAAA==.',
Je='Jessabella:BAAALgADCgQJBAAAAA==.Jesyikaxyz:BAAALgAECgkJCgAAAA==.',
Ji='Jifycornbred:BAAALgAECgMJAwAAAA==.Jigles:BAAALgAECgEJAQAAAA==.',
['Jä']='Jägermeister:BAAALgAECgIJBAABLgAECgUJBQALAAAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kalypso:BAAALgADCgkJCQAAAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8gAAIKAAkJzQV4XwAOAQAKAAkJzQV4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgAECgUJBgAAAA==.',
Ki='Kialla:BAAALgADCgYJCQABLgAECgkJGAABAH4YAA==.Kiraneem:BAABLgAECn8sAAMOAAkJUBrkJQA+AgAOAAkJUBrkJQA+AgAPAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn9DAAMKAAkJHBYTHQBXAgAKAAkJHBYTHQBXAgADAAQJZgyebwCKAAAAAA==.',
Ko='Kongfupanda:BAAALgAECgYJBgAAAA==.Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8XAAIEAAgJchCAfQB2AQAEAAgJchCAfQB2AQAAAA==.Krinj:BAABLgAECn8oAAIQAAkJZh0PRADvAQAQAAkJZh0PRADvAQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgAECgQJBAAAAA==.',
Ky='Kyarla:BAABLgAECn8jAAIZAAUJ6hUxNgAYAQAZAAUJ6hUxNgAYAQAAAA==.Kydo:BAACLgAFFH8HAAIEAAMJfQk2gADRAAAEAAMJfQk2gADRAAAuAAQKfyYAAgQABwm9GAFkAK8BAAQABwm9GAFkAK8BAAAA.Kythera:BAAALgAECgQJBwAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn82AAMIAAkJTRQqFwAIAgAIAAkJTRQqFwAIAgAZAAEJpQq8cwAgAAAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECgkJMQAWADMgAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9bAAIXAAkJoR78CACKAgAXAAkJoR78CACKAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgQJBQAAAA==.Lovécoil:BAAALgAECgEJAQAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn80AAIJAAkJvxnRCwCkAgAJAAkJvxnRCwCkAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8kAAQFAAkJGBneLQAEAgAFAAkJlxbeLQAEAgARAAMJ7BF1PgCqAAAaAAEJZw5nMQAyAAAAAA==.',
['Lë']='Lëw:BAAALgAFFAEJAQAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQALAAAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAABLgAECn8ZAAIbAAgJLwpoDABDAQAbAAgJLwpoDABDAQAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8gAAIZAAkJBR9KCgC1AgAZAAkJBR9KCgC1AgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECgcJEAAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAACLgAFFH8FAAMcAAMJVRlUGABXAAANAAIJhRdphgClAAAcAAEJ8xxUGABXAAAuAAQKfx0AAw0ACQl4JYw4ACkCAA0ABwnEJYw4ACkCAAwAAwm6InEnACYBAAAA.',
Me='Medreaux:BAABLgAECn9NAAIZAAkJuhx/CQDDAgAZAAkJuhx/CQDDAgAAAA==.Metalknyte:BAABLgAECn8sAAISAAkJRxD/FwCXAQASAAkJRxD/FwCXAQAAAA==.',
Mi='Miniknyte:BAABLgAECn8fAAIUAAkJBAwuSwBYAQAUAAkJBAwuSwBYAQAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiDbCQAVAgAHAAcJiiDbCQAVAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mogden:BAAALgAFFAEJAQABLgAECgkJIAAFAIIgAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJSwAAAA==.Morghulis:BAAALgAECgUJBQAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.Mukakin:BAAALgADCgEJAQAAAA==.',
My='Mychelle:BAABLgAECn83AAMdAAkJVRZUEAAoAgAdAAkJ3hJUEAAoAgAPAAgJ3hUACwCtAQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn84AAIEAAgJ6QmpjABYAQAEAAgJ6QmpjABYAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgUJDAALAAAAAA==.Nezaeth:BAAALgAECgUJDAAAAA==.Nezum:BAAALgADCggJEAABLgAECgUJDAALAAAAAA==.',
Ni='Nickoli:BAAALgAECgQJBAAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgMJAwAAAA==.Nojomoto:BAAALgAECgIJBAAAAA==.Norabel:BAAALgAECgYJDQAAAA==.',
Ny='Nyra:BAABLgAECn8qAAIOAAkJ6B6NEADCAgAOAAkJ6B6NEADCAgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn89AAMMAAkJbh3qAQCqAgAMAAkJbh3qAQCqAgANAAYJ2AskowD1AAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8fAAMeAAkJ2B6lDwBZAgAeAAkJ2B6lDwBZAgAUAAcJLQ4qXwA0AQABLgAFFAMJBQAEAEAEAA==.',
Ol='Oldben:BAABLgAFFH8GAAIBAAIJhwYAjwCCAAABAAIJhwYAjwCCAAAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAgJJAAfAJAfAA==.Oriel:BAABLgAECn8sAAIJAAkJXQoHJACgAQAJAAkJXQoHJACgAQAAAA==.Orthein:BAAALgAECgQJBgABLgAECgcJEAALAAAAAA==.',
Pa='Paleblueeye:BAAALgAECgEJAgAAAA==.Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgQJBAAAAA==.',
Ph='Phindin:BAABLgAECn84AAMDAAkJHRMUIwC/AQADAAkJHRMUIwC/AQAKAAcJxwXPdADuAAAAAA==.',
Pi='Pixystix:BAAALgADCgkJCQABLgAECgkJNwAdAFUWAA==.',
Po='Poc:BAABLgAECn8iAAIHAAgJHBERFABvAQAHAAgJHBERFABvAQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgAECgkJCwAAAA==.Primo:BAAALgAECgYJDAAAAA==.Prinsana:BAABLgAECn8sAAIYAAkJsBJHEACyAQAYAAkJsBJHEACyAQAAAA==.',
Pu='Puddytat:BAAALgADCgMJAwAAAA==.Purged:BAABLgAECn8gAAIKAAkJOAZPWgA/AQAKAAkJOAZPWgA/AQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Py='Pya:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Raidwipe:BAAALgADCgIJAgABLgAECgcJEAALAAAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgABLgAECgUJBQALAAAAAA==.Ratheer:BAABLgAFFH8FAAIFAAIJSRX0cQCIAAAFAAIJSRX0cQCIAAABLgAFFAMJBQAcAFUZAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8sAAIgAAgJ1htgEQCAAgAgAAgJ1htgEQCAAgAAAA==.',
Rh='Rhoana:BAAALgADCgcJBwAAAA==.',
Rl='Rllybuffnerd:BAAALgAECgIJAgAAAA==.',
Ro='Rodikus:BAACLgAFFH8KAAIZAAQJkRhaEAA5AQAZAAQJkRhaEAA5AQAuAAQKfz0AAxkACQnzIR8QAFkCABkACAldIh8QAFkCAAgACQmYFcoVABUCAAAA.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8jAAIFAAgJxRlBNADpAQAFAAgJxRlBNADpAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAVAJwPAA==.',
Ru='Rukus:BAAALgADCgQJBAAAAA==.',
['Rä']='Räwry:BAAALgAECgcJCAABLgAFFAMJCAAJAAoMAA==.',
Sa='Saiaa:BAAALgAECgkJEQAAAA==.Sakeena:BAAALgAECgQJBQAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAABLgAECn8WAAIIAAYJrAJcYACIAAAIAAYJrAJcYACIAAAAAA==.Sattia:BAABLgAECn9DAAIUAAkJzAYTWQAjAQAUAAkJzAYTWQAjAQAAAA==.',
Sc='Scampington:BAAALgAECgEJAwAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhjLGQAtAQAHAAYJXhjLGQAtAQAAAA==.',
Sh='Sharokk:BAAALgAECgcJBwABLgAECggJIwAFAMUZAA==.Sharrow:BAAALgAECgMJAwAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8sAAMTAAgJURL0JQB2AQATAAgJZxH0JQB2AQAVAAEJug9hkQA0AAAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn81AAIhAAkJUBxZDwB5AgAhAAkJUBxZDwB5AgAAAA==.Simphunter:BAEBLgAECn83AAIFAAkJfB4CEAC5AgAFAAkJfB4CEAC5AgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn8xAAIRAAkJPA4zGwCTAQARAAkJPA4zGwCTAQAAAA==.Sit:BAAALgAECgcJEAAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgiC/GQC6AgAFAAkJgiC/GQC6AgAAAA==.',
Sl='Slït:BAAALgADCgIJAgAAAA==.',
Sm='Smothbran:BAAALgADCgIJAwAAAA==.',
Sn='Snapdragon:BAAALgAECgQJBgAAAA==.',
So='Soluna:BAAALgAECgQJBAAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgQJBQAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwATABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn8jAAIPAAkJxxOaCADnAQAPAAkJxxOaCADnAQAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgQJBQAAAA==.Stillwing:BAAALgADCgIJAgAAAA==.Stormkraa:BAAALgAECgkJBgAAAA==.Strawyà:BAAALgADCgQJBwABLgAECgkJOgAYANEbAA==.Strawyæ:BAABLgAECn86AAIYAAkJ0Ru2BwBUAgAYAAkJ0Ru2BwBUAgAAAA==.Strike:BAAALgAECgYJCAABLgAFFAUJEgAgAGYUAA==.',
Su='Sugerfree:BAAALgAECgYJDAAAAA==.Suttercane:BAAALgAECgYJCQAAAA==.',
['Sì']='Sìrocco:BAAALgAECgYJBwAAAA==.',
Ta='Taleranor:BAAALgAECgcJEwAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8sAAMdAAkJhRPvEQAXAgAdAAkJZxHvEQAXAgAPAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgYJCAAAAA==.Teekeez:BAABLgAECn8bAAIEAAgJmQhpvAAKAQAEAAgJmQhpvAAKAQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgAECgIJAgAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn83AAIhAAkJAheuGQAaAgAhAAkJAheuGQAaAgAAAA==.Thorek:BAAALgADCgkJEAAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.Thunderracks:BAAALgAECgEJAQAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAABLgAFFAYJCwAEAGoVAA==.Tralle:BAAALgAECgMJAwAAAA==.Trapology:BAAALgAECgEJAgAAAA==.Trisky:BAABLgAECn8rAAMgAAkJ1Bi+GwAbAgAgAAgJjxe+GwAbAgABAAcJNQ5tmQA2AQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwALAAAAAA==.Trydént:BAAALgAECgQJBQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAABLgAECn8dAAMNAAYJzhqUWACPAQANAAYJzhqUWACPAQAMAAIJmwbdQQAiAAABLgAFFAMJBwASAJkfAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Un='Unhenged:BAAALgADCgQJBAAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8sAAIiAAkJCyHxBQB0AgAiAAkJCyHxBQB0AgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.',
Ve='Vegito:BAABLgAECn8zAAIhAAgJfAXESwAOAQAhAAgJfAXESwAOAQAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgAECgIJAgAAAA==.Vistus:BAAALgAECgcJCwAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECgkJNwAdAFUWAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RIZkwDsAAAFAAYJ+RIZkwDsAAABLgAECggJKgAOALchAA==.Voin:BAABLgAECn9aAAMjAAkJkSTdAQAwAwAjAAkJkSTdAQAwAwAhAAQJfRvkUAD8AAAAAA==.Vorpine:BAABLgAECn8zAAMIAAkJQBdOHgDnAQAIAAcJkBlOHgDnAQAJAAkJpAzhHwDAAQAAAA==.',
Vs='Vs:BAACLgAFFH8HAAIQAAMJ3RJHJQABAQAQAAMJ3RJHJQABAQAuAAQKfxUAAhAACAnYIKhSAPoBABAACAnYIKhSAPoBAAEuAAUUCQk6AAUAJCIA.',
Wa='Wallach:BAAALgAECgUJCgAAAA==.Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8cAAMkAAgJZxZbIwDwAQAkAAgJZxZbIwDwAQAVAAEJHgbbqwAhAAAAAA==.',
Wi='Winterberrie:BAAALgADCgYJBAAAAA==.Wirhl:BAABLgAECn8WAAIOAAYJ0RCtiAAgAQAOAAYJ0RCtiAAgAQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8OAAIBAAQJQyCmIQBsAQABAAQJQyCmIQBsAQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB8+MQAwAgABAAgJRB8+MQAwAgAAAA==.',
Xa='Xalbit:BAABLgAECn8rAAIKAAkJkhuREQC2AgAKAAkJkhuREQC2AgAAAA==.Xanae:BAAALgAECggJBgAAAA==.Xanthrash:BAAALgAECgcJEAAAAA==.Xantia:BAABLgAECn85AAIUAAkJJBbKHQBOAgAUAAkJJBbKHQBOAgAAAA==.Xaraena:BAABLgAECn8fAAIOAAkJfRr2KAATAgAOAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBgAAAA==.Xenlo:BAAALgAECgcJDwABLgAFFAQJEQAgAKIdAA==.',
Xy='Xyndrä:BAAALgADCgYJBgAAAA==.',
Yu='Yungun:BAAALgAECgEJAQAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJGAAlAH8YAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwALAAAAAA==.',
Ze='Zercus:BAABLgAFFH8MAAIBAAQJXQk+TgACAQABAAQJXQk+TgACAQAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJCwABLgAECggJMAAZAFYTAA==.',
['Ðr']='Ðread:BAABLgAECn8hAAMWAAgJog6PDwBrAQAWAAgJUQ6PDwBrAQAQAAYJEQynugD8AAAAAA==.',
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
