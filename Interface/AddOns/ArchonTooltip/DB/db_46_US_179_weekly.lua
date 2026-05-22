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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Fire','Unknown-Unknown','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','Warrior-Fury','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Preservation','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Druid-Guardian','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Druid-Feral','Mage-Arcane','Paladin-Holy','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECgUJBQAAAA==.Adynne:BAAALgAECgYJBgABLgAECgcJGgABADsfAA==.',
Ae='Aered:BAAALgAECgUJCwAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Ah='Ahira:BAABLgAECn8zAAICAAkJFCKxAwA9AwACAAkJFCKxAwA9AwAAAA==.',
Ai='Ailov:BAAALgADCgMJAwAAAA==.',
Ak='Akuria:BAABLgAECn8iAAIDAAkJvxhZFQDSAQADAAkJvxhZFQDSAQAAAA==.',
Al='Alahna:BAAALgAECgYJEQAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAABLgAECn8qAAMEAAgJAw5IGQAmAQAEAAgJAw5IGQAmAQAFAAQJSQJa+gCHAAAAAA==.Antamoon:BAAALgAECgQJBgAAAA==.',
Aq='Aquarian:BAAALgAECgYJCwAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgUJCwAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn8sAAMGAAgJfhPaOABsAQAGAAgJfhPaOABsAQAHAAQJpAXKSgCMAAAAAA==.Aurna:BAAALgAECgcJDwAAAA==.',
Ba='Babegnome:BAAALgAECgEJAQAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgYJEAAAAA==.',
Be='Beartank:BAAALgADCgYJBgAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8MAAIIAAQJVhjWGABnAQAIAAQJVhjWGABnAQAuAAQKf00AAwgACQn3JN0FAKUDAAgACQn3JN0FAKUDAAkAAQndIZMKAFwAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJHAAIAAoeAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAAALgAECgYJDQAAAA==.Beroldin:BAAALgADCgIJAgABLgAECgYJDQAKAAAAAA==.Bevar:BAAALgADCgYJBwABLgAECgQJCAAKAAAAAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAILAAYJoB7QJQDVAQALAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8WAAIEAAkJjh8uBABoAgAEAAkJjh8uBABoAgAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAgAAAA==.Blindmafaka:BAAALgAECgQJBAAAAA==.Blkrend:BAABLgAECn8/AAIEAAkJKyaLAAD2AgAEAAkJKyaLAAD2AgAAAA==.',
Br='Bradycam:BAABLgAECn8tAAIMAAkJoRk1GwBiAgAMAAkJoRk1GwBiAgAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJBwAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgIJAQAAAA==.Bruddah:BAAALgAFFAEJAQABLgAFFAMJDAANAPMKAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJAwAAAA==.Carebeär:BAABLgAECn8aAAIGAAcJ6hcYNgDPAQAGAAcJ6hcYNgDPAQAAAA==.Casella:BAABLgAECn8/AAILAAkJgSDFAwDhAgALAAkJgSDFAwDhAgAAAA==.',
Ce='Celissara:BAAALgAECgUJDwABLgAECgcJDwAKAAAAAA==.',
Ch='Chimken:BAAALgADCgMJAwAAAA==.Chogori:BAAALgAECgMJCQAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn8aAAIMAAcJdxZbVACFAQAMAAcJdxZbVACFAQAAAA==.Clouzot:BAAALgADCgUJBwAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn8gAAIOAAcJoAbWDAD/AAAOAAcJoAbWDAD/AAAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8UAAQPAAYJ1Q5xHgBzAAAQAAQJygwGlwDRAAAPAAMJzwxxHgBzAAARAAMJ5QzyGwBlAAAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwASACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAABLgAECn8jAAMTAAgJHReoBgC8AQATAAgJShWoBgC8AQAFAAgJ5xBBVQB/AQAAAA==.Danskan:BAAALgAECgYJDQAAAA==.Darkvale:BAAALgAECgMJAwAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8gAAIUAAgJRRYVFADAAQAUAAgJRRYVFADAAQAAAA==.Dashii:BAAALgAECgEJAgAAAA==.Datewoo:BAABLgAECn8WAAIMAAYJLQ/GlQD/AAAMAAYJLQ/GlQD/AAAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deef:BAAALgAECgQJBAAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgMJBQABLgADCgkJLgAKAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Devoroyal:BAAALgAECgcJEQAAAA==.Dez:BAAALgAECgUJBQABLgAECggJIgAFAM4HAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgUJCwAAAA==.',
Do='Donkaßutts:BAAALgAECgQJBQAAAA==.Dooda:BAAALgAECgQJCgAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgUJCQAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECgcJGgABADsfAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAAALgAECgUJBQAAAA==.Dracfu:BAABLgAECn8XAAIVAAgJpQfeNwD9AAAVAAgJpQfeNwD9AAABLgAECgkJDgAKAAAAAA==.Dracserion:BAAALgAECgUJBQABLgAFFAQJDAAIAFYYAA==.Dracsknight:BAAALgAECgkJDgAAAA==.Dracslana:BAAALgAECgUJCwABLgAECgkJDgAKAAAAAA==.Draffel:BAABLgAECn8YAAMCAAgJihupEgBmAgACAAgJihupEgBmAgAWAAEJxQH8iwAWAAAAAA==.Drathi:BAABLgAECn8VAAIEAAcJ4Q9NGgAdAQAEAAcJ4Q9NGgAdAQAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drowgon:BAABLgAECn8WAAMXAAcJYBfjJACCAQAXAAcJYBfjJACCAQANAAYJfw3YJgCzAAAAAA==.Druwgon:BAAALgAECgEJAQAAAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8NAAISAAQJNQ2KNAAHAQASAAQJNQ2KNAAHAQAuAAQKfyQAAxIABwk9G7kvAD0CABIABwk9G7kvAD0CABgABAlCDWQaAMEAAAAA.Dunzer:BAABLgAECn8vAAMMAAkJyhelOwA1AgAMAAkJyhelOwA1AgABAAIJQwkBNABKAAAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8ZAAIGAAYJ9hurKwC1AQAGAAYJ9hurKwC1AQAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8cAAIIAAgJCh7wOgCLAgAIAAgJCh7wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgcJDwAKAAAAAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8YAAIZAAkJqh8PBQC6AgAZAAkJqh8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgAECgQJBwAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgAECgUJDAAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwAAAA==.',
Er='Eradoria:BAAALgAECgYJEQAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgEJAQAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECgYJBgAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8XAAIaAAgJGAkyEwBLAQAaAAgJGAkyEwBLAQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAAKAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJBgABLgAECgYJGQAGAPYbAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgIJAwAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAgABLgAFFAQJDAAIAFYYAA==.Fenn:BAABLgAECn8sAAIWAAkJdxi6DgA1AgAWAAkJdxi6DgA1AgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Fistantillus:BAAALgAECgcJCgAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fonddle:BAAALgADCgUJCQAAAA==.Foxyboo:BAABLgAECn8vAAICAAkJ1hsTDACvAgACAAkJ1hsTDACvAgAAAA==.',
Fr='Freak:BAABLgAECn8YAAMGAAgJHhI7NACEAQAGAAgJHhI7NACEAQAHAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgQJCQAAAA==.',
Ga='Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgQJCQAAAA==.',
Ge='Gertroz:BAAALgAECgMJBQABLgAECgcJDwAKAAAAAA==.',
Gn='Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn8tAAIbAAkJLCWDAQBfAwAbAAkJLCWDAQBfAwAAAA==.Gope:BAABLgAECn8fAAMCAAkJXhU2OQBsAQACAAkJXhU2OQBsAQAWAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Green:BAABLgAECn8WAAIUAAgJSxcbCQBUAgAUAAgJSxcbCQBUAgAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn8uAAMUAAkJSyJHAgD6AgAUAAkJdCFHAgD6AgAcAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJLgAUAEsiAA==.Grr:BAABLgAECn8mAAISAAkJZSGoCADVAgASAAkJZSGoCADVAgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gó']='Gójira:BAAALgAECgYJCgAAAA==.',
Ha='Hartis:BAABLgAECn8sAAQbAAkJERA/MgDDAQAbAAkJERA/MgDDAQAUAAIJqwQ2QABcAAAcAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgQJBAAAAA==.Hazo:BAABLgAECn8eAAMLAAYJOwniTQCQAAALAAUJMQriTQCQAAAdAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgEJAQAAAA==.Hellkat:BAAALgAECgUJBwAAAA==.',
Hi='Higarosa:BAAALgADCgIJAwAAAA==.Highbull:BAAALgAECgEJAQAAAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Holiblade:BAABLgAECn8vAAIMAAgJogl6fwAmAQAMAAgJogl6fwAmAQAAAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgABLgAECgcJFwACALwSAA==.Hooligun:BAABLgAECn8jAAIWAAgJ8g51KwBCAQAWAAgJ8g51KwBCAQAAAA==.',
Hu='Huntlord:BAAALgADCgcJBwAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAAALgAECgkJEwAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8cAAIBAAcJfA2PFwAQAQABAAcJfA2PFwAQAQAAAA==.',
Ij='Ijustshotyou:BAAALgAECgQJDQABLgAFFAIJBQAMANQDAA==.',
Il='Illyría:BAAALgADCgcJBwAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAECggJJQAQAO4dAA==.Jakob:BAAALgAECgEJAgAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jardal:BAAALgADCgUJDAAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8ZAAIbAAYJmxFTaAAYAQAbAAYJmxFTaAAYAQAAAA==.Jenanila:BAAALgAECgEJAgAAAA==.',
Ji='Jibbs:BAABLgAECn8iAAMFAAgJzgdVgwAVAQAFAAcJrAhVgwAVAQAEAAEJmALtSQAcAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwAKAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJDQAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn8gAAIeAAcJNhJZFgAoAQAeAAcJNhJZFgAoAQAAAA==.Jonnygordo:BAAALgAECgUJDAAAAA==.Jorahh:BAABLgAECn8WAAMWAAcJHRaLJABvAQAWAAYJHRaLJABvAQACAAcJ2AysYAAJAQAAAA==.',
Ju='Jugram:BAAALgADCgkJHAAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8eAAIbAAgJ8h5yFgCEAgAbAAgJ8h5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8ZAAIEAAgJ/BjkEgBqAQAEAAgJ/BjkEgBqAQAAAA==.',
['Jø']='Jønty:BAAALgADCgUJDAAAAA==.',
Ka='Kaelyra:BAAALgADCgUJDAAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJLgACANUhAA==.',
Ke='Keelhorn:BAABLgAECn8iAAICAAkJGRREIgDrAQACAAkJGRREIgDrAQAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJBQAHAKoOAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8UAAMPAAYJ4gU9HQCAAAAQAAYJ0wR4ogC7AAAPAAQJfgQ9HQCAAAAAAA==.Kinkyhawt:BAEALgAECgYJEgAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn8UAAIfAAcJBwNVTAC9AAAfAAcJBwNVTAC9AAAAAA==.',
Ko='Kodiakk:BAABLgAECn8YAAIUAAYJwRVrIABMAQAUAAYJwRVrIABMAQAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Kramden:BAAALgADCgcJDgAAAA==.Krattos:BAAALgAECgIJAwAAAA==.Krimzin:BAAALgAECgEJAQABLgAFFAQJDAAbAHIbAA==.',
Ku='Kuddles:BAAALgADCgEJBQAAAA==.Kumei:BAAALgADCgMJAwABLgAECgkJLAAbABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJojAA==.',
Kw='Kwazii:BAABLgAECn8gAAQgAAgJfBdqJgC5AQAgAAgJfBdqJgC5AQADAAYJ+wUSPQDIAAAhAAEJGwbjXAApAAAAAA==.',
Ky='Kyantzmi:BAAALgAECgMJBAAAAA==.Kyogre:BAAALgAECgYJDQAAAA==.',
La='Laefnia:BAABLgAECn8cAAUHAAgJARU+JwA6AQAHAAcJlhE+JwA6AQAGAAUJvhW0ZQAhAQAeAAEJ8hKYQAA0AAAiAAEJNAZ9NQAuAAAAAA==.Laraydra:BAAALgAECgUJCQABLgAECgcJDwAKAAAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAdAD0QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leomist:BAAALgAECggJEQAAAA==.Leviosä:BAABLgAECn8sAAIIAAkJBhOhOwDrAQAIAAkJBhOhOwDrAQAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJHQAAAA==.Lilis:BAAALgADCgcJCwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8tAAIFAAkJYiS5BQAiAwAFAAkJYiS5BQAiAwAAAA==.Liten:BAAALgADCgUJDAAAAA==.Littlebev:BAAALgAECgQJCAAAAA==.',
Lo='Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgUJCwAAAA==.',
['Lí']='Lírii:BAAALgAECgcJEQAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn8zAAQRAAgJmx9kAwAcAgARAAgJmx9kAwAcAgAPAAcJhBVMGwByAQAQAAEJjBCN7AA+AAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Malaurray:BAABLgAECn8aAAIQAAgJ9wqHWgBSAQAQAAgJ9wqHWgBSAQABLgABCgQJBgAKAAAAAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAAALgAECgkJCgAAAA==.',
Mc='Mcchong:BAAALgADCgQJBAAAAA==.Mckennah:BAABLgAECn8aAAMBAAcJOx/3BwAEAgABAAcJOx/3BwAEAgAMAAEJDgzGNQE0AAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAECgcJIAAIABEVAA==.Mereidith:BAABLgAECn8gAAMIAAcJERXNewBFAQAIAAcJARTNewBFAQAjAAEJchoTGQBPAAAAAA==.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8pAAMkAAgJrgeXOQAUAQAkAAgJrgeXOQAUAQAMAAIJyQG/UgEkAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJHAAIAAoeAA==.Miriya:BAABLgAECn8jAAILAAkJyCQvAQBFAwALAAkJyCQvAQBFAwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIdAAcJPRDvKAAiAQAdAAcJPRDvKAAiAQAAAA==.Moobáca:BAAALgAECgUJBwAAAA==.Moostradamas:BAABLgAECn8bAAMTAAgJ7wVFEADyAAATAAgJ7wVFEADyAAAFAAIJsgAcLwEhAAAAAA==.Morcilla:BAAALgAECgcJDgAAAA==.',
Ms='Msg:BAABLgAECn8hAAIGAAgJlx0cEwBwAgAGAAgJlx0cEwBwAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgUJCwAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nastrodamus:BAAALgAECgEJAQAAAA==.Naturegoob:BAABLgAECn8bAAMGAAgJqBogNADYAQAGAAgJqBogNADYAQAHAAMJ4RGARAClAAAAAA==.Naughtynurse:BAABLgAECn8qAAIGAAkJShALKADMAQAGAAkJShALKADMAQAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIMAAQJBAveuQDDAAAMAAQJBAveuQDDAAAAAA==.',
Ni='Nicfurry:BAAALgADCgIJAgAAAA==.Nightflower:BAABLgAECn8jAAMjAAkJUwUhDwDRAAAIAAcJGQW4ngAFAQAjAAYJAwQhDwDRAAAAAA==.',
No='Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJCgABLgAECgYJDQAKAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAABLgAECn8/AAIMAAkJ8iA7CQDsAgAMAAkJ8iA7CQDsAgAAAA==.Obietide:BAAALgAECgYJCAABLgAECgkJPwAMAPIgAA==.',
Od='Oddball:BAABLgAECn8eAAIWAAkJBhwTDwAwAgAWAAkJBhwTDwAwAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEAAAAA==.',
Ok='Okamiblooded:BAAALgAECgUJBwAAAA==.',
Ol='Olly:BAAALgAECgUJBQAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAAALgAECgYJEQAAAA==.',
Or='Orangekeg:BAAALgAECgUJEQABLgAECgkJHwAWANkfAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgMJBwAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn8uAAIEAAkJMh3NBgApAgAEAAkJMh3NBgApAgABLgAECggJKAABAJojAA==.Peso:BAAALgAECgMJAwAAAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8LAAIVAAUJ7AwwEgBGAQAVAAUJ7AwwEgBGAQABLgAFFAQJCAAkAGESAA==.Pomater:BAAALgAECgQJBgABLgAECgcJDwAKAAAAAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAIIAAgJOQmadgBPAQAIAAgJOQmadgBPAQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECggJKwACACUiAA==.',
Pr='Primafox:BAAALgAECgQJCgAAAA==.Prkchopxpres:BAAALgAECgYJDgAAAA==.Protoheal:BAAALgADCgEJAQAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.',
['Pä']='Päw:BAACLgAFFH8FAAMFAAMJbwupbgCXAAAFAAMJbwupbgCXAAATAAEJ8QIJEwA8AAAuAAQKfx8AAgUACAlNFw06ANQBAAUACAlNFw06ANQBAAAA.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Radge:BAABLgAECn8lAAMlAAgJjiH+AgDkAgAlAAgJVSH+AgDkAgAXAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8FAAMUAAMJ1xfHFwC8AAAUAAIJ/BnHFwC8AAAbAAEJjRNeXgBSAAAuAAQKfzwAAxsACQn/IZsIANcCABQACQlcH14CAB8DABsACAk3JJsIANcCAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8kAAIBAAgJxx0kCwAaAgABAAgJxx0kCwAaAgAAAA==.Ralanar:BAAALgAECgYJCAABLgAECgcJDwAKAAAAAA==.Raljah:BAABLgAECn8yAAQRAAgJhiRlAQCYAgARAAgJeiRlAQCYAgAQAAcJ6B6rGgBKAgAPAAUJFh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn8ZAAIBAAcJ7xebDQCUAQABAAcJ7xebDQCUAQAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgAKAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJAwAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAAALgAECgcJEQAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8PAAIhAAMJkhq3GwD6AAAhAAMJkhq3GwD6AAAuAAQKfxUAAyEACAmMGVIRAC4CACEACAmMGVIRAC4CAAMAAQk4FfxcADwAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgUJDAAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.',
Ry='Ryobi:BAABLgAECn8lAAMbAAgJSRQVNAC7AQAbAAgJHhQVNAC7AQAcAAcJdgmREwDBAAAAAA==.',
['Ræ']='Rævena:BAAALgAECgcJCQAAAA==.',
Sa='Sachaann:BAAALgAECgEJAQAAAA==.Salinan:BAABLgAECn8/AAMRAAkJsSSBAAD/AgARAAkJsSSBAAD/AgAQAAQJqBdKlgDTAAAAAA==.Saltymon:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJIQAmADkZAA==.Saric:BAAALgADCgYJBgAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8WAAIMAAYJnBrfWQB3AQAMAAYJnBrfWQB3AQAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAABLgAECn8UAAIXAAcJ+wc+OQASAQAXAAcJ+wc+OQASAQAAAA==.',
Sh='Shak:BAAALgAECgYJCAAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJCgABLgAECggJMwARAJsfAA==.Shellingtun:BAAALgAECgYJCwAAAA==.Shyandrial:BAAALgADCgkJHwAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8ZAAIDAAgJjgmuKAA2AQADAAgJjgmuKAA2AQAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDAAAAA==.Skullyy:BAAALgAECgIJBAABLgAECgYJDQAKAAAAAA==.Skychades:BAAALgAECgYJDgAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAIHAAcJohC8JwA3AQAHAAcJohC8JwA3AQAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgEJAQABLgAECgcJHAAHAKIQAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgEJAgAAAA==.Soulsrequiem:BAABLgAECn8VAAInAAcJJwEMGABmAAAnAAcJJwEMGABmAAAAAA==.',
Sp='Spicyblaster:BAAALgAFFAMJAwAAAA==.Spookydeath:BAACLgAFFH8JAAIIAAMJbwnuXwDiAAAIAAMJbwnuXwDiAAAuAAQKfycAAggACQm2D+c+AN8BAAgACQm2D+c+AN8BAAAA.',
Sr='Srsnacksalot:BAABLgAECn8dAAIMAAgJiBRUSACnAQAMAAgJiBRUSACnAQAAAA==.',
St='Stileto:BAAALgAECgcJDgAAAA==.Stoneydracco:BAAALgAECgYJEAAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgUJCwAAAA==.',
Su='Sukiliana:BAAALgAECgMJBAAAAA==.Sumtinwng:BAABLgAECn8nAAIMAAgJtQ8EWQB6AQAMAAgJtQ8EWQB6AQAAAA==.Supervicious:BAABLgAECn8VAAINAAgJohOoFABZAQANAAgJohOoFABZAQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgUJDAAAAA==.Sylenne:BAABLgAECn8tAAIGAAkJDRZpFwBFAgAGAAkJDRZpFwBFAgAAAA==.Sylur:BAAALgAECgQJBQABLgAECgYJGQAGAPYbAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAECgEJAQABLgAFFAQJEQAhABAYAA==.Tahren:BAACLgAFFH8RAAQhAAQJEBgwFgAzAQAhAAQJFBQwFgAzAQAgAAEJvCXRHwBrAAADAAEJiw/oJABSAAAuAAQKfyMABCAACAltIHMQAGECACAABwn0IHMQAGECACEACAmwEVgrAEABAAMABAn1DZRRAGMAAAAA.Talanima:BAAALgADCgcJBwAAAA==.Talerion:BAAALgAECgYJEAAAAA==.',
Tc='Tcdots:BAAALgAECgEJAQAAAA==.',
Te='Tens:BAABLgAECn8bAAIXAAgJJiNXDAD1AgAXAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgUJCwAAAA==.Theafflictor:BAAALgAECgUJBwAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgUJCwAKAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn8fAAIdAAcJCAaKNADjAAAdAAcJCAaKNADjAAAAAA==.Thrallsux:BAAALgAECgEJAQAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn8vAAMMAAgJCBOiagCpAQAMAAgJCBOiagCpAQABAAcJdgsAAAAAAAAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8bAAMVAAYJxxvGGwDBAQAVAAYJxxvGGwDBAQAdAAQJqg+ZTQDbAAAAAA==.Tokidormi:BAAALgAECgcJBwAAAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgIJAgAAAA==.',
Tr='Tralku:BAAALgAECgcJBwAAAA==.Tremmørs:BAABLgAECn8dAAIWAAcJ5As4OwDxAAAWAAcJ5As4OwDxAAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAAALgAECgcJCwAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweak:BAAALgAECgIJAgAAAA==.Tweis:BAAALgADCgUJDAAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8XAAMmAAkJZhhmFACpAQAmAAkJZhhmFACpAQAnAAEJPA23HQA/AAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Valaa:BAAALgAECgUJBQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8VAAIMAAkJOg4CcgCYAQAMAAkJOg4CcgCYAQAAAA==.Vellestrix:BAAALgAECgMJAwAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Viddysouls:BAABLgAECn8YAAIZAAYJnRUzEAA7AQAZAAYJnRUzEAA7AQAAAA==.Viscerai:BAABLgAECn8vAAIgAAgJDibbAQBkAwAgAAgJDibbAQBkAwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAIRAAIJLhUJBgClAAARAAIJLhUJBgClAAAuAAQKfxgAAxEABwn5FUAGAPkBABEABwn5FUAGAPkBABAAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECggJMwARAJsfAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgcJHAAHAKIQAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Wanted:BAABLgAECn8hAAImAAkJORmXCQBAAgAmAAkJORmXCQBAAgAAAA==.Warfaxis:BAABLgAECn8UAAIXAAcJ9CDnDwA0AgAXAAcJ9CDnDwA0AgAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAGAB4SAA==.',
Wi='Winnower:BAAALgADCgYJBgAAAA==.Wiseoldgoob:BAAALgAECgkJEQAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAECgcJCwAAAA==.',
Ze='Zenclaw:BAABLgAECn8jAAIVAAkJSA2pIQCQAQAVAAkJSA2pIQCQAQAAAA==.Zencore:BAABLgAECn8VAAIIAAgJdw+EZAB2AQAIAAgJdw+EZAB2AQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQAIAHcPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQAIAHcPAA==.',
Zi='Ziel:BAAALgAECgkJCgABLgAECgkJIwALAMgkAA==.',
['Ñö']='Ñövä:BAAALgADCgMJBAAAAA==.',
['ßu']='ßubba:BAAALgAECgQJCQAAAA==.',
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
