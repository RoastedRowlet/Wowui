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

local lookup = {'Paladin-Protection','Shaman-Restoration','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','DeathKnight-Unholy','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Mage-Frost','Mage-Fire','Unknown-Unknown','Monk-Brewmaster','Paladin-Retribution','Warrior-Protection','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','Warrior-Fury','DemonHunter-Vengeance','Shaman-Enhancement','DemonHunter-Havoc','Evoker-Preservation','Hunter-Marksmanship','Monk-Windwalker','Druid-Guardian','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Druid-Feral','Mage-Arcane','Paladin-Holy','Warrior-Arms','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acile:BAAALgADCgEJAQAAAA==.',
Ad='Adhenar:BAAALgAECgMJAwAAAA==.Adow:BAAALgAECgUJBQAAAA==.Adynne:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.',
Ae='Aered:BAAALgAECgYJDQAAAA==.Aerev:BAAALgAECgEJAwAAAA==.Aerylith:BAAALgAECgYJCgAAAA==.',
Af='Aften:BAAALgAECgYJCAAAAA==.',
Ah='Ahira:BAABLgAECn80AAICAAkJqiLkBQA/AwACAAkJqiLkBQA/AwAAAA==.',
Ai='Ailov:BAAALgADCgMJAwAAAA==.',
Ak='Akuria:BAABLgAECn8zAAIDAAkJSBx/CgCMAgADAAkJSBx/CgCMAgAAAA==.',
Al='Alacía:BAAALgAECgYJBwAAAA==.Alahna:BAABLgAECn8ZAAIEAAgJSgiGbgBMAQAEAAgJSgiGbgBMAQAAAA==.Alliesrofl:BAAALgADCgEJAQAAAA==.Aluzan:BAAALgADCgUJBQAAAA==.',
An='Anahera:BAAALgADCgYJCQAAAA==.Anies:BAACLgAFFH8FAAIFAAIJyQPYLABdAAAFAAIJyQPYLABdAAAuAAQKfzwAAwUACQkoDZEbAGQBAAUACQkoDZEbAGQBAAYABQm/Alr6AIcAAAAA.Antamoon:BAAALgAECgYJEQAAAA==.',
Ao='Aox:BAABLgAECn8qAAIHAAkJfRoeDABMAgAHAAkJfRoeDABMAgAAAA==.',
Aq='Aquarian:BAAALgAECgYJDAAAAA==.',
Ar='Ardcore:BAAALgAECgYJDgAAAA==.Arkæ:BAAALgADCgkJAQAAAA==.Arys:BAAALgAECgEJAQAAAA==.',
As='Asherrylie:BAAALgADCgYJDQAAAA==.Ashtrây:BAAALgADCgMJBAAAAA==.Assasincross:BAAALgAECgMJAwAAAA==.Asseroth:BAAALgAECgEJAQAAAA==.',
At='Atriux:BAAALgAECgkJCAAAAA==.',
Au='Aureline:BAABLgAECn80AAMIAAkJXRNAMQDIAQAIAAkJXRNAMQDIAQAJAAQJpAV3XACFAAAAAA==.Aurna:BAAALgAFFAEJAQAAAA==.',
Ba='Babegnome:BAAALgAECgEJAgAAAA==.Backstrap:BAAALgADCgQJBAAAAA==.Batmuhn:BAAALgAECgcJEQAAAA==.',
Be='Beanfliker:BAAALgADCgIJAgAAAA==.Beartank:BAAALgADCgYJBgAAAA==.Beastiam:BAAALgAECgEJAgAAAA==.Beastquake:BAAALgADCgMJAwAAAA==.Beefpunch:BAAALgAECgMJAwAAAA==.Belaseth:BAAALgADCgUJCAAAAA==.Belserion:BAACLgAFFH8QAAIKAAQJwRjWGABnAQAKAAQJwRjWGABnAQAuAAQKf1wAAwoACQnoJRMDAGYDAAoACQnoJRMDAGYDAAsAAQndIesNAFcAAAAA.Bendoverman:BAAALgAECgEJAQABLgAECgkJIQAKANEfAA==.Bernir:BAAALgAECgIJAgAAAA==.Berol:BAAALgAECgYJDwAAAA==.Beroldin:BAAALgADCgIJAgABLgAECgYJDwAMAAAAAA==.Bevar:BAAALgAECgEJAQABLgAECgUJDAAMAAAAAA==.Bevell:BAAALgADCgQJBQABLgAECgUJDAAMAAAAAA==.',
Bi='Bigboiexx:BAAALgAECgMJAwAAAA==.Biggiebrewz:BAABLgAECn8WAAINAAYJoB7QJQDVAQANAAYJoB7QJQDVAQAAAA==.Biggielocks:BAAALgADCgkJCQAAAA==.Biggiesdk:BAABLgAECn8aAAIFAAkJjh9kBQDCAgAFAAkJjh9kBQDCAgAAAA==.Biggieshan:BAAALgAECgUJBQAAAA==.',
Bl='Blackmaster:BAAALgAECgEJAwAAAA==.Blair:BAAALgAECgEJAgAAAA==.Blindmafaka:BAAALgAECgYJEAAAAA==.Blkrend:BAABLgAECn9NAAIFAAkJKybRAABdAwAFAAkJKybRAABdAwAAAA==.Bloodhound:BAAALgAECgYJBgAAAA==.Blurtaxes:BAAALgAECgcJAgAAAA==.',
Bo='Bonko:BAAALgAECgMJAwAAAA==.',
Br='Bradycam:BAABLgAECn82AAIOAAkJSh4yEQDIAgAOAAkJSh4yEQDIAgAAAA==.Braffermac:BAAALgAECgIJBAAAAA==.Brewmaster:BAAALgAECgcJCAAAAA==.Brightwing:BAAALgAECgYJBwAAAA==.Bruceelee:BAAALgADCgMJAwAAAA==.Bruddah:BAAALgAFFAIJAwABLgAFFAMJDAAPAPMKAA==.',
Bu='Bubblebutt:BAAALgAECgUJBQAAAA==.Bulloo:BAAALgAECgEJAwAAAA==.',
['Bó']='Bóbafett:BAAALgADCgEJAQAAAA==.',
Ca='Cadovenia:BAAALgAECgEJBAAAAA==.Camillerose:BAAALgAECgQJBAAAAA==.Cantpalyhard:BAAALgAECgYJCAABLgAECgkJSgACAI0gAA==.Carebeär:BAABLgAECn8gAAIIAAcJ6hcYNgDPAQAIAAcJ6hcYNgDPAQAAAA==.Carpediems:BAAALgADCgIJAQAAAA==.Casella:BAABLgAECn8/AAINAAkJkSC7BQDTAgANAAkJkSC7BQDTAgAAAA==.',
Ce='Celissara:BAAALgAECgYJEQABLgAFFAEJAQAMAAAAAA==.',
Ch='Chimken:BAAALgADCgMJAwAAAA==.Chogori:BAAALgAECgMJCQAAAA==.Chôsenône:BAAALgAECgUJBgAAAA==.',
Cl='Clawmydia:BAAALgADCgYJBwAAAA==.Cleth:BAABLgAECn8sAAIOAAkJKR2JFgCmAgAOAAkJKR2JFgCmAgAAAA==.Clouzot:BAAALgADCgYJDAAAAA==.',
Co='Content:BAAALgADCgMJAwAAAA==.Corax:BAABLgAECn8xAAIQAAkJewklCQCFAQAQAAkJewklCQCFAQAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8fAAQRAAcJpRC4HAC2AAASAAQJSg7EsADYAAARAAQJshC4HAC2AAATAAMJzwwsJQBvAAAAAA==.',
Cr='Crane:BAAALgADCgUJBQAAAA==.Crankitty:BAAALgAECgMJBwAAAA==.Crispee:BAAALgADCgEJAQAAAA==.Critshot:BAAALgAECgYJEAABLgAFFAMJBwAUACEdAA==.Crunchylock:BAAALgAECggJDAAAAA==.',
Cu='Cunumi:BAAALgAECgQJBAAAAA==.',
Cy='Cyllar:BAAALgADCgYJBgAAAA==.',
['Cö']='Cösmic:BAAALgAECgIJAgAAAA==.',
Da='Damachi:BAABLgAECn8wAAMVAAkJSBj+BABFAgAVAAkJ8hf+BABFAgAGAAgJ5xDkawB5AQAAAA==.Danskan:BAAALgAECgYJEgAAAA==.Darkvale:BAAALgAECgYJCQAAAA==.Darkñess:BAAALgAECggJDQAAAA==.Darmorae:BAABLgAECn8jAAIWAAkJsRWjEgAHAgAWAAkJsRWjEgAHAgAAAA==.Dashii:BAAALgAECgEJAgAAAA==.Datewoo:BAABLgAECn8iAAIOAAgJbRIHZQCMAQAOAAgJbRIHZQCMAQAAAA==.',
De='Deadstimpy:BAAALgADCgcJBwAAAA==.Deef:BAAALgAECgUJCQAAAA==.Demilia:BAAALgAECgQJBAAAAA==.Demontotem:BAAALgAECgUJBQAAAA==.Derasande:BAAALgADCgEJAQAAAA==.Desadeness:BAAALgADCgMJBQABLgADCgkJMAAMAAAAAA==.Desertpunk:BAAALgAECgEJAQAAAA==.Destrolock:BAAALgAECgYJCwABLgAFFAIJCAAOAJEdAA==.Devoroyal:BAAALgAFFAEJAQAAAA==.Dez:BAAALgAECgUJBQABLgAECgkJJQAGAKUHAA==.',
Di='Diasuke:BAAALgADCgQJBAAAAA==.Dillinquent:BAAALgAECgYJDQAAAA==.',
Do='Donkaßutts:BAAALgAECgQJDQAAAA==.Dooda:BAAALgAECgQJCgAAAA==.Doodooboi:BAAALgAECgQJBAAAAA==.Doomclaw:BAAALgADCgQJBAAAAA==.Doomforge:BAAALgAECgYJCwAAAA==.Dorciaa:BAAALgAECgYJBgABLgAECggJHgABAG4hAA==.Dottinstds:BAAALgAECgYJBgAAAA==.',
Dr='Dracbow:BAABLgAECn8UAAIEAAgJZRHORwCyAQAEAAgJZRHORwCyAQABLgAECgkJGQAGAPQQAA==.Dracfu:BAABLgAECn8XAAIXAAgJpgc+TwD6AAAXAAgJpgc+TwD6AAABLgAECgkJGQAGAPQQAA==.Drackpally:BAAALgAECgcJAwAAAA==.Dracserion:BAAALgAECgkJDAABLgAFFAQJEAAKAMEYAA==.Dracsham:BAAALgADCgEJAQABLgAECgkJGQAGAPQQAA==.Dracsknight:BAABLgAECn8ZAAIGAAkJ9BDhQwDkAQAGAAkJ9BDhQwDkAQAAAA==.Dracslana:BAAALgAECgUJDAABLgAECgkJGQAGAPQQAA==.Draffel:BAABLgAECn8hAAMCAAkJuxt8EAC0AgACAAkJuxt8EAC0AgAYAAEJxQGbrQAVAAAAAA==.Drathi:BAABLgAECn8bAAMFAAcJABLQJQALAQAFAAcJ4g/QJQALAQAGAAQJnRKPuADxAAAAAA==.Drestla:BAAALgAECgcJCwAAAA==.Drowgon:BAABLgAECn8YAAMZAAgJEheHLgCCAQAZAAcJORiHLgCCAQAPAAcJ8g3PJwDbAAAAAA==.Drtot:BAAALgAECgEJAQAAAA==.Druwgon:BAAALgAECgIJAgAAAA==.',
Du='Duartor:BAAALgAECgIJAgAAAA==.Dukalune:BAAALgAECgUJCQAAAA==.Dukaos:BAACLgAFFH8OAAIUAAQJqQ9lPwAPAQAUAAQJqQ9lPwAPAQAuAAQKfzUAAxQACAmgHdAiADACABQACAmgHdAiADACABoABAlCDWQaAMEAAAAA.Dunzer:BAABLgAECn9IAAMOAAkJrRrpIgBiAgAOAAkJrRrpIgBiAgABAAIJQwkhQABJAAAAAA==.Dunzerblaze:BAAALgAECgQJCAAAAA==.',
['Dé']='Déadeye:BAAALgAECgEJAQAAAA==.',
['Dõ']='Dõrã:BAAALgADCgcJBwAAAA==.',
['Dø']='Døømlørd:BAABLgAECn8dAAIIAAgJJBv0GgBaAgAIAAgJJBv0GgBaAgAAAA==.',
['Dú']='Dúbs:BAAALgADCgMJAwAAAA==.',
Ea='Earthhammerz:BAAALgAECgEJAQAAAA==.',
Ed='Edithpoothe:BAABLgAECn8hAAIKAAgJ0R/wOgCLAgAKAAgJ0R/wOgCLAgAAAA==.',
Eh='Ehonda:BAAALgAECgUJBQABLgAECgkJGQAFAJQPAA==.',
Ei='Eightt:BAAALgADCgcJCwAAAA==.',
El='Electricks:BAABLgAECn8YAAIbAAkJqh8PBQC6AgAbAAkJqh8PBQC6AgAAAA==.Ellaryia:BAAALgADCgMJAwAAAA==.',
Em='Emmii:BAAALgAECgYJDQAAAA==.Emolock:BAAALgAECgUJBQAAAA==.',
En='Endlessbuns:BAAALgAECgUJCwAAAA==.Enset:BAAALgADCgUJBQAAAA==.Enyetia:BAAALgADCgcJBwAAAA==.',
Eo='Eon:BAAALgAECgUJDwAAAA==.',
Ep='Epiphaný:BAAALgAECgYJCwAAAA==.',
Er='Eradoria:BAABLgAECn8UAAIcAAYJQgXmRADiAAAcAAYJQgXmRADiAAAAAA==.Erielea:BAAALgADCgcJCAAAAA==.Erilock:BAAALgAECgQJBAAAAA==.',
Es='Essylt:BAAALgAECgQJBQAAAA==.Este:BAAALgADCgQJBAAAAA==.',
Ev='Evadne:BAAALgAECggJDQAAAA==.Evagrius:BAAALgAECgUJBQAAAA==.Evalin:BAAALgADCgEJAQAAAA==.Evoken:BAABLgAECn8aAAIdAAkJzgmBEwB+AQAdAAkJzgmBEwB+AQAAAA==.',
Ex='Exidore:BAAALgAECgcJDAAAAA==.',
Fa='Faant:BAAALgADCgYJCgABLgAECgQJBAAMAAAAAA==.Faeroline:BAAALgAECgYJBwAAAA==.Falchionx:BAAALgAECgUJCwABLgAECggJHQAIACQbAA==.Falfogan:BAAALgAECgEJAgAAAA==.Fangy:BAAALgAECgIJAwAAAA==.Fatone:BAAALgAECgQJCAAAAA==.',
Fe='Felserion:BAAALgADCgEJAgABLgAFFAQJEAAKAMEYAA==.Fenn:BAABLgAECn81AAIYAAkJXBnzEABUAgAYAAkJXBnzEABUAgAAAA==.Fenrìs:BAAALgADCgUJBAAAAA==.',
Fi='Fistantillus:BAAALgAECgcJCgAAAA==.',
Fl='Flane:BAAALgADCggJBQAAAA==.Flopper:BAAALgAECgYJCwAAAA==.',
Fo='Fonddle:BAAALgADCgUJCQAAAA==.Foxyboo:BAABLgAECn9KAAMCAAkJjSAZBQBNAwACAAkJjSAZBQBNAwAYAAEJ8wU4pgAiAAAAAA==.',
Fr='Freak:BAABLgAECn8YAAMIAAgJHhJCPgCHAQAIAAgJHhJCPgCHAQAJAAYJsgk6TQD1AAAAAA==.Freakpeachh:BAAALgAECgMJAwAAAA==.Frorly:BAAALgAECgEJAQAAAA==.',
Fu='Fulv:BAAALgAECgUJEAAAAA==.',
['Fâ']='Fâith:BAAALgAECgQJCgAAAA==.',
Ga='Gaezßuleaux:BAAALgAECgQJBQAAAA==.Galerodra:BAAALgADCgEJAQAAAA==.Galorani:BAAALgADCgIJAgAAAA==.Gammin:BAAALgAECgEJAQAAAA==.Ganajir:BAAALgADCgcJBwAAAA==.Garalline:BAAALgAECgcJDgAAAA==.',
Ge='Gertroz:BAAALgAECgUJCAABLgAFFAEJAQAMAAAAAA==.',
Gi='Gimic:BAAALgAECggJEAAAAA==.',
Gn='Gnomatic:BAAALgADCgEJAQABLgAECgkJJQAGAKUHAA==.Gnumb:BAAALgADCgIJAgAAAA==.',
Go='Gooberetta:BAABLgAECn8uAAIEAAkJLSXBAwBHAwAEAAkJLSXBAwBHAwAAAA==.Gope:BAABLgAECn8lAAMCAAkJRBdAHQBJAgACAAkJRBdAHQBJAgAYAAQJ3gZMdgBpAAAAAA==.Gorriten:BAAALgADCgIJAgAAAA==.',
Gr='Green:BAABLgAECn8WAAIWAAgJSxcbCQBUAgAWAAgJSxcbCQBUAgAAAA==.Grewsome:BAAALgAECgMJAwAAAA==.Grimdoll:BAAALgAECgEJAQAAAA==.Grmreaper:BAAALgADCgUJBQAAAA==.Gromiir:BAABLgAECn8yAAMWAAkJSyJJBADgAgAWAAkJdCFJBADgAgAeAAgJ3R0MEgCoAgAAAA==.Gromyr:BAAALgAECgEJAQABLgAECgkJMgAWAEsiAA==.Grr:BAABLgAECn8rAAIUAAkJZiECCgDpAgAUAAkJZiECCgDpAgAAAA==.',
Gy='Gynchi:BAAALgAECgcJCgAAAA==.Gytha:BAAALgADCgIJAgAAAA==.',
['Gä']='Gärrus:BAAALgAECgQJBAAAAA==.',
['Gó']='Gójira:BAAALgAECgcJEQAAAA==.',
Ha='Hartis:BAABLgAECn8sAAQEAAkJERDKLgD2AQAEAAkJERDKLgD2AQAWAAIJqwRhTgBaAAAeAAQJ5wBdewBWAAAAAA==.Hashmal:BAAALgAECgUJBwAAAA==.Hazo:BAABLgAECn8iAAMNAAYJbgmeWgCPAAANAAUJcQqeWgCPAAAfAAMJqAQbbABfAAAAAA==.',
He='Healingman:BAAALgADCgUJBQAAAA==.Hectabali:BAAALgADCgYJBQAAAA==.Heizou:BAAALgAECgYJBwABLgAFFAMJCQAGAMkOAA==.Hellkat:BAAALgAECgUJBwAAAA==.',
Hi='Higarosa:BAAALgADCgIJAwAAAA==.Highbull:BAAALgAECgUJBQAAAA==.Hild:BAAALgAECgkJAQAAAA==.',
Ho='Holiblade:BAABLgAECn83AAIOAAgJ7gnsmwAiAQAOAAgJ7gnsmwAiAQAAAA==.Holyfaxiss:BAEALgAECggJEQABLgAECggJJAAZAMkeAA==.Holyhannah:BAAALgAECgUJBgAAAA==.Holykilla:BAAALgAECgUJDwAAAA==.Holyshiva:BAAALgADCgcJCgAAAA==.Hooligun:BAABLgAECn8uAAIYAAgJRRA1NABPAQAYAAgJRRA1NABPAQAAAA==.Hoppered:BAAALgAECgUJBgABLgAECgkJOwARAOAiAA==.',
Hu='Huntinpowerz:BAAALgAECgEJAQAAAA==.Huntlord:BAAALgADCgcJBwAAAA==.',
Hy='Hypérian:BAAALgAECgQJBAAAAA==.',
Ia='Iamtrash:BAAALgAECgQJBAAAAA==.Iantha:BAABLgAECn8TAAIEAAkJSBt1PgC1AQAEAAkJSBt1PgC1AQAAAA==.',
Ic='Icyprotoss:BAAALgAECgEJAQAAAA==.',
Ig='Igglybuff:BAABLgAECn8iAAIBAAcJ9RAkGABCAQABAAcJ9RAkGABCAQAAAA==.',
Ih='Ihatereports:BAAALgAECgQJCAABLgAFFAMJBQAEAHgHAA==.',
Ij='Ijustshotyou:BAACLgAFFH8FAAMEAAMJeAcLcACOAAAEAAIJzAcLcACOAAAWAAIJiwRlJgCIAAAuAAQKfxUABB4ACAl4DwgUAAkBAB4ABwnNDggUAAkBABYAAglBDqpIAHoAAAQAAgm+DgDaAG0AAAAA.',
Il='Illyría:BAAALgADCgcJBwAAAA==.Ilovetouka:BAAALgAECgMJBQAAAA==.',
Ir='Ironlotss:BAAALgADCgkJDQAAAA==.',
Ja='Jags:BAAALgADCgUJBwABLgAFFAMJBQASAD0QAA==.Jakob:BAAALgAECgEJAwAAAA==.Jaks:BAAALgADCgEJAQAAAA==.Jardal:BAAALgADCgYJEQAAAA==.Jayyo:BAAALgAECgIJAgAAAA==.',
Je='Jehbodia:BAABLgAECn8gAAIEAAYJ/REOgwAgAQAEAAYJ/REOgwAgAQAAAA==.Jenanila:BAAALgAECgMJBAAAAA==.',
Jh='Jhenna:BAAALgAECgEJAQABLgAECgkJLwAIAB8WAA==.',
Ji='Jibbs:BAABLgAECn8lAAMGAAkJpQcXiQA9AQAGAAgJXQgXiQA9AQAFAAEJmAKaXQAZAAAAAA==.Jimmyhalpert:BAAALgADCgIJAgAAAA==.',
Jn='Jnymango:BAAALgAECgIJBAABLgAECgMJAwAMAAAAAA==.',
Jo='Joanexotic:BAAALgAECgYJEAAAAA==.Johnnysham:BAAALgAECgMJAwAAAA==.Jolah:BAAALgAECgIJAgAAAA==.Jollakeratu:BAABLgAECn8xAAIgAAkJJRPPDgDWAQAgAAkJJRPPDgDWAQAAAA==.Jonnygordo:BAABLgAECn8VAAIOAAYJBg5TsQABAQAOAAYJBg5TsQABAQAAAA==.Jorahh:BAABLgAECn8XAAMYAAcJHRYTLwBrAQAYAAYJHRYTLwBrAQACAAcJ2QysYAAJAQAAAA==.',
Ju='Jugram:BAAALgAECgQJBAAAAA==.Jungolv:BAAALgADCgMJAwAAAA==.Jusmissiner:BAABLgAECn8iAAIEAAkJxx5yFgCEAgAEAAkJxx5yFgCEAgAAAA==.Jussmissiner:BAAALgADCgYJCQAAAA==.Juut:BAABLgAECn8cAAIFAAgJzBuyEwC8AQAFAAgJzBuyEwC8AQAAAA==.',
['Jø']='Jønty:BAAALgADCgYJEQAAAA==.',
Ka='Kaelyra:BAAALgADCgYJEQAAAA==.Kaitenn:BAAALgAECgYJBgAAAA==.Kamehame:BAAALgAECggJEgAAAA==.Kaseus:BAAALgAECgIJAgAAAA==.',
Kb='Kbetty:BAAALgADCgcJBwABLgAECgkJNwACACoiAA==.',
Ke='Keelhorn:BAABLgAECn8kAAMCAAkJGRSVLQDnAQACAAkJGRSVLQDnAQAYAAIJDQcegwBNAAAAAA==.Kenneth:BAAALgAECgcJEgAAAA==.Kevin:BAAALgAECgYJDAABLgAFFAUJCQAJAIgXAA==.Keyadorath:BAAALgADCgIJAgAAAA==.',
Ki='Kibon:BAABLgAECn8ZAAMTAAYJsga1IwB4AAASAAYJ9AU/twDNAAATAAQJfgS1IwB4AAAAAA==.Kinkyhawt:BAEBLgAECn8WAAMhAAYJkh11JwCLAQAQAAUJchuiFQCUAQAhAAYJ+Rx1JwCLAQAAAA==.Kirio:BAAALgADCgcJCgAAAA==.Kitsunenohi:BAABLgAECn8lAAIcAAkJYAaWJgAgAQAcAAkJYAaWJgAgAQAAAA==.',
Ko='Kodiakk:BAABLgAECn8fAAIWAAgJTBRxGQDEAQAWAAgJTBRxGQDEAQAAAA==.Kozilek:BAAALgADCgQJBAAAAA==.',
Kr='Kramden:BAAALgADCgkJEwAAAA==.Krattos:BAAALgAECgIJAwAAAA==.Krechon:BAAALgADCgQJBAAAAA==.Krimzin:BAAALgAECgEJAQABLgAFFAUJFgAEAHwgAA==.',
Ks='Ksares:BAAALgAECgIJAgABLgAECgkJUAAEANwhAA==.',
Ku='Kuddles:BAAALgADCgEJBwAAAA==.Kumei:BAAALgAECgEJAQABLgAECgkJLAAEABEQAA==.Kural:BAAALgAECgUJBgABLgAECggJKAABAJsjAA==.',
Kw='Kwazii:BAABLgAECn8mAAQiAAgJ/BeEGgDeAQAiAAgJ/BeEGgDeAQADAAYJ+wWGTQCyAAAjAAIJJAWOXQBWAAAAAA==.',
Ky='Kyantzmi:BAABLgAECn8UAAIHAAYJNgxCJgBHAQAHAAYJNgxCJgBHAQAAAA==.Kyogre:BAABLgAECn8XAAIJAAcJjBGeLgBMAQAJAAcJjBGeLgBMAQAAAA==.',
La='Laefnia:BAACLgAFFH8GAAMJAAMJQA0IKwCxAAAJAAMJQA0IKwCxAAAIAAEJ0w+hYQA9AAAuAAQKfykABQkACQkZGNgXAPcBAAkACAnnGNgXAPcBAAgABgnaErRlACEBACAAAgkOEb1JAF0AACQAAQk0Bn01AC4AAAEuAAUUAwkJAAYAyQ4A.Laraydra:BAAALgAECgUJDAABLgAFFAEJAQAMAAAAAA==.Lastofgoobs:BAAALgADCgQJBAAAAA==.Latias:BAAALgADCgUJBQABLgAECgcJGQAfAD4QAA==.Lavaburstya:BAAALgAECgcJDAAAAA==.',
Le='Leomist:BAABLgAECn8ZAAIXAAkJVw9mKgCsAQAXAAkJVw9mKgCsAQAAAA==.Leviosä:BAABLgAECn89AAMKAAkJOxjCKgBYAgAKAAkJOxjCKgBYAgALAAEJ2wahEgAlAAAAAA==.',
Li='Liden:BAAALgADCgMJAwAAAA==.Lildarleena:BAAALgADCgkJHQAAAA==.Lilis:BAAALgADCgcJCwAAAA==.Lilithe:BAAALgAECgIJAQAAAA==.Lillíth:BAABLgAECn8uAAIGAAkJZCTSCQARAwAGAAkJZCTSCQARAwAAAA==.Liten:BAAALgADCgYJEQAAAA==.Littlebev:BAAALgAECgUJDAAAAA==.',
Lo='Lockmender:BAAALgAECgMJAwAAAA==.Logonman:BAAALgAECgYJBwAAAA==.Longshankss:BAAALgAECgUJDAAAAA==.',
Ly='Lynaiya:BAAALgADCgMJAwAAAA==.',
['Lé']='Léxí:BAAALgAECgkJCQAAAA==.',
['Lí']='Lírii:BAAALgAECggJEgAAAA==.',
['Lô']='Lôôbmeup:BAAALgADCgEJAQAAAA==.',
Ma='Maachen:BAAALgAECgYJCwAAAA==.Maalik:BAABLgAECn9JAAQRAAkJ7CAfAQDuAgARAAkJpSAfAQDuAgATAAcJfxpqCACqAQASAAMJgw5r6wBvAAAAAA==.Magejackky:BAAALgAECgQJCAAAAA==.Magiclaw:BAAALgAECgEJAQAAAA==.Maivorkeru:BAAALgAECgQJBgAAAA==.Malaurray:BAABLgAECn8jAAISAAgJbQzWZgBlAQASAAgJbQzWZgBlAQABLgABCgQJBgAMAAAAAA==.Maluin:BAAALgAECgEJAQAAAA==.Mavanta:BAAALgAECgMJBAAAAA==.Mayonæse:BAABLgAECn8UAAIUAAUJQgnsmgDMAAAUAAUJQgnsmgDMAAAAAA==.',
Mc='Mcchong:BAAALgAECgMJAwAAAA==.Mckennah:BAABLgAECn8eAAMBAAgJbiF/BQCBAgABAAgJbiF/BQCBAgAOAAEJDgxCeQEvAAAAAA==.',
Me='Mereideath:BAAALgADCgMJAwABLgAFFAMJBQAKAJEJAA==.Mereidith:BAACLgAFFH8FAAIKAAMJkQn3dgDUAAAKAAMJkQn3dgDUAAAuAAQKfycAAwoABwlYF1RxAH0BAAoABwlYF1RxAH0BACUAAQlyGhMZAE8AAAAA.Meshulk:BAAALgAECgEJAQAAAA==.Mesohungry:BAABLgAECn8pAAMmAAgJrgeQRQASAQAmAAgJrgeQRQASAQAOAAIJzAHkjAEoAAAAAA==.Metasploit:BAAALgAECgkJAQAAAA==.',
Mi='Mikehunte:BAAALgAECgYJBgABLgAECgkJIQAKANEfAA==.Miriya:BAABLgAECn8jAAINAAkJyCT/AQA6AwANAAkJyCT/AQA6AwAAAA==.Missnoms:BAAALgAECgEJAQAAAA==.',
Mo='Monkeycheese:BAABLgAECn8ZAAIfAAcJPhB2MwAgAQAfAAcJPhB2MwAgAQAAAA==.Moobáca:BAAALgAECgUJBwAAAA==.Moostradamas:BAABLgAECn8eAAMVAAgJTgYfGQDWAAAVAAgJTgYfGQDWAAAGAAIJsgAacgEgAAAAAA==.Morcilla:BAAALgAECggJEwAAAA==.Morticyde:BAAALgAECgMJBAAAAA==.',
Ms='Msg:BAABLgAECn8lAAIIAAkJrBvDEgCkAgAIAAkJrBvDEgCkAgAAAA==.',
Mu='Munassa:BAAALgADCgcJBwAAAA==.Muppets:BAAALgAECgUJCQAAAA==.',
My='Myssidia:BAAALgADCgYJEAAAAA==.',
['Mí']='Mínervä:BAAALgAECgkJCQAAAA==.',
Na='Naleria:BAAALgADCgYJBgAAAA==.Narisa:BAAALgAECgIJAwAAAA==.Nastrodamus:BAAALgAECgEJAQAAAA==.Naturegoob:BAABLgAECn8bAAMIAAgJphogNADYAQAIAAgJphogNADYAQAJAAMJ4RHjVACgAAAAAA==.Naughtynurse:BAABLgAECn8zAAIIAAkJxhHMKwDoAQAIAAkJxhHMKwDoAQAAAA==.Nayee:BAAALgADCgUJBQAAAA==.',
Ne='Nemrak:BAAALgAFFAIJAgAAAA==.Neuma:BAABLgAECn8UAAIOAAQJBAvM8ACqAAAOAAQJBAvM8ACqAAAAAA==.',
Ni='Nicfurry:BAAALgADCgMJAwAAAA==.Nightflower:BAABLgAECn8kAAMlAAkJUwUhDwDRAAAKAAcJGQVLwADqAAAlAAYJAwQhDwDRAAAAAA==.',
No='Noided:BAAALgAECgYJCgAAAA==.Novadots:BAAALgAECgEJAgAAAA==.',
Ny='Nyxon:BAAALgAECgYJDgABLgAECgYJEAAMAAAAAA==.',
['Nä']='Nätê:BAAALgAECgMJAwAAAA==.',
['Nî']='Nîbbles:BAAALgAECgIJAgAAAA==.',
Ob='Obiejuan:BAABLgAECn9RAAMOAAkJ4CJ2CgD/AgAOAAkJ4CJ2CgD/AgABAAQJoB5oHgAIAQAAAA==.Obietide:BAAALgAECgkJEQABLgAECgkJUQAOAOAiAA==.',
Od='Oddball:BAABLgAECn8eAAIYAAkJBhzCFQAgAgAYAAkJBhzCFQAgAgAAAA==.',
Of='Ofthecircle:BAAALgAECggJEwAAAA==.',
Ok='Okamiblooded:BAAALgAECgYJDQAAAA==.',
Ol='Olly:BAAALgAECgUJBwAAAA==.',
On='Ontala:BAAALgADCgYJBgAAAA==.',
Oo='Oodles:BAAALgAECgcJEgAAAA==.',
Or='Orangecrush:BAAALgAECgEJAQAAAA==.Orangekeg:BAAALgAECgUJEQABLgAECgkJIQAYANgfAA==.Oritoko:BAAALgAECgQJBAAAAA==.Orthiaa:BAAALgAECgYJDQAAAA==.',
Pa='Palpinaintez:BAAALgAECgYJDgAAAA==.Parras:BAAALgAECgEJAQAAAA==.',
Pe='Penzarion:BAAALgADCgUJBQAAAA==.Perison:BAABLgAECn88AAIFAAkJ2R11CAB7AgAFAAkJ2R11CAB7AgABLgAECggJKAABAJsjAA==.Peso:BAAALgAECgQJBwAAAA==.Pez:BAAALgAECgUJCgABLgAECgkJLwAIAB8WAA==.',
Ph='Phaidon:BAAALgAECgcJCQAAAA==.',
Po='Pokeylock:BAAALgADCggJCAAAAA==.Polyhedroll:BAABLgAFFH8RAAIXAAYJfRHyFACFAQAXAAYJfRHyFACFAQABLgAFFAQJCAAmAGESAA==.Pomater:BAAALgAECgQJBwABLgAFFAEJAQAMAAAAAA==.Postmalorne:BAAALgADCgMJAwAAAA==.Potatopp:BAABLgAECn8YAAIKAAgJOQknkQA7AQAKAAgJOQknkQA7AQAAAA==.',
Pp='Ppincoke:BAAALgADCgEJAQABLgAECgkJLAACALQgAA==.',
Pr='Primafox:BAAALgAECgQJCgAAAA==.Prkchopxpres:BAAALgAECgYJDwAAAA==.Protoheal:BAAALgAECgEJAQAAAA==.',
Pu='Punchandkick:BAAALgAECgMJBgAAAA==.',
Py='Pyrabanks:BAAALgAECgYJCwAAAA==.',
['Pä']='Päw:BAACLgAFFH8JAAMGAAMJyQ5SigDTAAAGAAMJyQ5SigDTAAAVAAIJSQQlGQB6AAAuAAQKfyQAAwYACAk+GH9LAM0BAAYACAlOF39LAM0BABUAAQmTHCApAFMAAAAA.',
Qu='Quetzalcóatl:BAAALgAECgQJBAAAAA==.Quickclaw:BAAALgADCgEJAQAAAA==.Quivermethis:BAAALgAECgEJAgAAAA==.',
Qx='Qx:BAAALgADCggJDgAAAA==.',
Ra='Raakoth:BAAALgAECgUJBQABLgAECgkJSQARAOwgAA==.Radge:BAABLgAECn8xAAMnAAkJ/SQmAQBSAwAnAAkJ+yQmAQBSAwAZAAMJKR0rdgDiAAAAAA==.Rainjar:BAACLgAFFH8NAAMWAAQJhiD3EwAgAQAWAAMJRSD3EwAgAQAEAAIJkBscXwCuAAAuAAQKfzwAAxYACQkAIl4CAB8DABYACQlcH14CAB8DAAQACAk3JDMPAMMCAAAA.Rainne:BAAALgADCgcJCAAAAA==.Raistyn:BAABLgAECn8pAAMBAAkJwRw5CgAOAgABAAkJwRw5CgAOAgAOAAEJigxvfQEtAAAAAA==.Ralanar:BAAALgAECgcJDQABLgAFFAEJAQAMAAAAAA==.Raljah:BAABLgAECn87AAQRAAkJ4CLDAAAPAwARAAkJ1CLDAAAPAwASAAcJ7B69JQA6AgATAAUJXh19FACnAQAAAA==.Ramasus:BAAALgAECgUJBQAAAA==.Rampart:BAABLgAECn8nAAIBAAgJMBmXCwD0AQABAAgJMBmXCwD0AQAAAA==.Rasaltghul:BAAALgAECgEJAQABLgAECgMJBgAMAAAAAA==.Rashomon:BAAALgAECgEJAQAAAA==.Raxxer:BAAALgAECgEJBAAAAA==.',
Re='Recklessfury:BAAALgADCgYJAgAAAA==.Reignasmite:BAABLgAECn8UAAMBAAcJtw2LIwDcAAAOAAcJ9gcqvgDtAAABAAYJbg6LIwDcAAAAAA==.Reiko:BAAALgADCgUJBQAAAA==.Renm:BAAALgAECgYJEgAAAA==.Renpriest:BAACLgAFFH8UAAIjAAMJfx4YIgAIAQAjAAMJfx4YIgAIAQAuAAQKfxUAAyMACAmMGVIRAC4CACMACAmMGVIRAC4CAAMAAQk4FTxxADsAAAAA.',
Rh='Rhaege:BAAALgADCgUJBgAAAA==.',
Ro='Rokk:BAAALgADCgUJDAAAAA==.Rolemiso:BAAALgADCgEJAQAAAA==.',
Ry='Ryobi:BAABLgAECn8vAAMEAAkJmhTqLAASAgAEAAkJmhTqLAASAgAeAAcJdgnlFgDoAAAAAA==.Ryptyde:BAABLgAECn8WAAICAAkJ7h5pBgA1AwACAAkJ7h5pBgA1AwAAAA==.',
['Ræ']='Rævena:BAAALgAECgcJEAAAAA==.',
Sa='Sachaann:BAAALgAECgIJAwAAAA==.Salinan:BAABLgAECn9RAAMRAAkJ3CSBAAAvAwARAAkJtySBAAAvAwASAAYJ7RqfTwCgAQAAAA==.Saltymon:BAAALgADCgYJBgABLgAECgIJAwAMAAAAAA==.Saox:BAAALgAECgYJCAABLgAECgkJKgAHAH0aAA==.Saradia:BAAALgADCgIJAgAAAA==.Saric:BAAALgAECgMJBAAAAA==.Satanownsyou:BAAALgADCgEJAQAAAA==.',
Sc='Scanor:BAAALgAECgYJCgABLgAFFAMJCgAhAD8CAA==.Schûltz:BAAALgADCgMJAwAAAA==.Scoop:BAAALgAECgYJBQAAAA==.',
Se='Seleñe:BAAALgAECgEJAQAAAA==.Selinedion:BAABLgAECn8iAAIOAAgJdxsmKwA8AgAOAAgJdxsmKwA8AgAAAA==.Selky:BAAALgADCgcJCgAAAA==.',
Sf='Sfodin:BAABLgAECn8dAAIZAAgJKQmvOQBKAQAZAAgJKQmvOQBKAQAAAA==.',
Sh='Shadowkings:BAAALgAECgMJBgAAAA==.Shak:BAABLgAECn8aAAIYAAYJ7QvWUADXAAAYAAYJ7QvWUADXAAAAAA==.Shalai:BAAALgADCgMJAwAAAA==.Shalynn:BAAALgADCgIJAgAAAA==.Shandra:BAAALgADCgcJCwAAAA==.Shastix:BAAALgAECgYJDwABLgAECgkJSQARAOwgAA==.Shellingtun:BAAALgAECgYJCwAAAA==.Shyandrial:BAAALgADCgkJIQAAAA==.',
Si='Siathena:BAAALgADCgMJAwAAAA==.Sintharia:BAABLgAECn8hAAIDAAgJ0QoyLwBCAQADAAgJ0QoyLwBCAQAAAA==.',
Sk='Skilltotem:BAAALgAECgkJEAAAAA==.Skk:BAAALgADCggJCQAAAA==.Sksteve:BAAALgAECgUJDwAAAA==.Skullyy:BAAALgAECgYJDgABLgAECgYJEAAMAAAAAA==.Skychades:BAAALgAECgYJDgAAAA==.',
Sl='Slammajamma:BAAALgAECgkJCQAAAA==.Slowpoke:BAABLgAECn8cAAIJAAcJohB/MwAwAQAJAAcJohB/MwAwAQAAAA==.Slyfauna:BAAALgAECgEJAQAAAA==.',
Sn='Snorlax:BAAALgAECgYJBwABLgAECgcJHAAJAKIQAA==.',
So='Sofakingroot:BAAALgADCgYJCQAAAA==.Soft:BAAALgAECgIJAgAAAA==.Softpaw:BAAALgADCgYJBgAAAA==.Soulrobber:BAAALgAECgcJDQAAAA==.Soulsrequiem:BAABLgAECn8fAAIoAAgJiwG9GACMAAAoAAgJiwG9GACMAAAAAA==.',
Sp='Spicyblaster:BAABLgAFFH8JAAIKAAQJBAlLWwAcAQAKAAQJBAlLWwAcAQAAAA==.Spookydeath:BAACLgAFFH8PAAIKAAQJ7ghMXwASAQAKAAQJ7ghMXwASAQAuAAQKfy0AAgoACQlUEqZHAO0BAAoACQlUEqZHAO0BAAAA.',
Sr='Srsnacksalot:BAABLgAECn8mAAIOAAgJ9hgyQQDqAQAOAAgJ9hgyQQDqAQAAAA==.',
St='Stileto:BAAALgAECgcJDgAAAA==.Stoneydracco:BAABLgAECn8XAAIKAAYJGxJzmAAtAQAKAAYJGxJzmAAtAQAAAA==.Stoneydragon:BAAALgADCgYJBgAAAA==.Stormpuppy:BAAALgADCgEJAQAAAA==.Sturnguard:BAAALgAECgYJDQAAAA==.',
Su='Sukiliana:BAAALgAECgMJBAAAAA==.Sumtinwng:BAABLgAECn81AAIOAAgJxRK+VgCuAQAOAAgJxRK+VgCuAQAAAA==.Supervicious:BAABLgAECn8YAAIPAAgJZBX2FgB0AQAPAAgJZBX2FgB0AQAAAA==.',
Sw='Swiftheålzz:BAAALgAECgYJCwAAAA==.',
Sy='Sydah:BAAALgADCgYJEQAAAA==.Sylenne:BAABLgAECn8vAAIIAAkJHxYqHQBJAgAIAAkJHxYqHQBJAgAAAA==.Sylur:BAAALgAECgcJDgABLgAECggJHQAIACQbAA==.',
['Sÿ']='Sÿlvanah:BAAALgAECgQJBAAAAA==.',
Ta='Taemea:BAAALgAECggJEgAAAA==.Tahran:BAAALgAECgEJAQABLgAFFAUJGAAjAC8XAA==.Tahren:BAACLgAFFH8YAAQjAAUJLxf6GABgAQAjAAUJmRH6GABgAQAiAAIJ5SI1GgDHAAADAAIJZgs1KQCGAAAuAAQKfycABCIACQmIIHMQAGECACIABwn0IHMQAGECACMACQlvE4EtAEkBAAMABgklD5ZSAJ0AAAAA.Talanima:BAAALgADCgcJBwAAAA==.Taler:BAAALgAECgUJBQAAAA==.Talerion:BAAALgAECgcJEgAAAA==.Talyaine:BAAALgAECgEJAQABLgAFFAMJCQAGAMkOAA==.Tanzanitia:BAAALgAECgYJBgAAAA==.',
Tc='Tcdots:BAAALgAECgEJAgAAAA==.',
Te='Tens:BAABLgAECn8bAAIZAAgJJiNXDAD1AgAZAAgJJiNXDAD1AgAAAA==.',
Th='Thatonemonk:BAAALgAECgYJDQAAAA==.Theafflictor:BAAALgAECgYJCQAAAA==.Theoneshaman:BAAALgADCgQJBAABLgAECgYJDQAMAAAAAA==.Thereaben:BAAALgADCggJCwAAAA==.Thistelbear:BAABLgAECn8uAAIfAAgJkwiNMwAfAQAfAAgJkwiNMwAfAQAAAA==.Thrallsux:BAAALgAECgEJAgAAAA==.Thraun:BAAALgAECgYJEgAAAA==.Thrâl:BAAALgAECgMJBgAAAA==.Thunderdin:BAABLgAECn8xAAMOAAkJQxKiagCpAQAOAAkJQxKiagCpAQABAAcJaAsaIgDoAAAAAA==.',
Ti='Titszilla:BAAALgAECgcJAwAAAA==.',
To='Toki:BAABLgAECn8bAAMXAAYJxxsMJwDBAQAXAAYJxxsMJwDBAQAfAAQJqg+ZTQDbAAAAAA==.Tokidormi:BAABLgAECn8UAAMdAAcJ1x1yCABXAgAdAAcJ1x1yCABXAgAQAAEJzQVpJQArAAAAAA==.Toralus:BAAALgADCgYJCQAAAA==.Totumm:BAAALgADCgcJCAAAAA==.',
Tr='Tralku:BAAALgAECgcJDAAAAA==.Tremmørs:BAABLgAECn8aAAIYAAcJUQx8SAD2AAAYAAcJUQx8SAD2AAAAAA==.Trixiie:BAAALgADCgQJBAAAAA==.Truezangetsu:BAAALgAFFAEJAgAAAA==.',
Tu='Turnip:BAAALgAECgEJAQAAAA==.',
Tw='Tweak:BAAALgAECgIJAgAAAA==.Tweis:BAAALgADCgYJEQAAAA==.',
Ty='Tyllinor:BAAALgADCgUJBQAAAA==.',
Um='Umbrarogue:BAABLgAECn8eAAMHAAkJOByoDgAoAgAHAAkJ0RqoDgAoAgAoAAEJPh2DHgBVAAAAAA==.',
Un='Unaires:BAAALgAECgEJAQAAAA==.',
Ur='Urzaa:BAAALgAECgUJEwAAAA==.',
Va='Vaara:BAAALgAECgEJAQAAAA==.Valaa:BAAALgAECgUJBQAAAA==.Valdan:BAAALgADCgQJBgAAAA==.',
Ve='Veddicus:BAAALgADCgEJAQAAAA==.Velien:BAABLgAECn8WAAIOAAkJyA4CcgCYAQAOAAkJyA4CcgCYAQAAAA==.Veliya:BAAALgAECgYJDQABLgAECgkJLwAIAB8WAA==.Vellestrix:BAAALgAECgQJBAAAAA==.Veppy:BAAALgADCgcJBwAAAA==.Vexare:BAAALgADCgYJBgAAAA==.Vexatious:BAAALgADCgUJBgAAAA==.Vexed:BAAALgADCgkJFAAAAA==.',
Vi='Vicotr:BAAALgAECgcJCQAAAA==.Viddysouls:BAABLgAECn8eAAIbAAYJnRWuFgA0AQAbAAYJnRWuFgA0AQAAAA==.Viscerai:BAABLgAECn84AAIiAAkJiSXvAAC9AwAiAAkJiSXvAAC9AwAAAA==.Vite:BAAALgAECgYJDwAAAA==.Vitta:BAAALgAECgMJAwAAAA==.',
Vo='Vonmiller:BAACLgAFFH8FAAIRAAIJLhUxDACXAAARAAIJLhUxDACXAAAuAAQKfxoAAxEABwkiFkAGAPkBABEABwkiFkAGAPkBABIAAgkSDPf7AGIAAAAA.Vozluz:BAAALgAECgEJAQABLgAECgkJSQARAOwgAA==.',
Vu='Vulpix:BAAALgADCgcJBwABLgAECgcJHAAJAKIQAA==.',
['Væ']='Væda:BAAALgAECgMJAwAAAA==.',
Wa='Warfaxis:BAEBLgAECn8kAAIZAAgJyR7aDQB+AgAZAAgJyR7aDQB+AgAAAA==.',
We='Weird:BAAALgAECgIJAgABLgAECgkJGAAIAB4SAA==.',
Wi='Winnower:BAAALgADCgYJBgAAAA==.Wiseoldgoob:BAAALgAECgkJEgAAAA==.',
Wr='Wratth:BAAALgAECgUJDQAAAA==.',
Ww='Ww:BAAALgAFFAIJBAAAAA==.',
Wy='Wyldpyre:BAAALgADCgMJCAAAAA==.',
Xe='Xennessa:BAAALgAFFAEJAQAAAA==.',
Ze='Zenclaw:BAABLgAECn8sAAIXAAkJsg4OKgCvAQAXAAkJsg4OKgCvAQAAAA==.Zencore:BAABLgAECn8VAAIKAAgJeA+9fQBiAQAKAAgJeA+9fQBiAQAAAA==.Zenfaith:BAAALgADCgIJAgABLgAECggJFQAKAHgPAA==.Zenlock:BAAALgADCgIJAgABLgAECggJFQAKAHgPAA==.',
Zi='Ziel:BAAALgAECgkJCwABLgAECgkJIwANAMgkAA==.',
Zo='Zoramite:BAAALgAECgUJBQAAAA==.',
['Äl']='Älexa:BAAALgAECgkJAQAAAA==.',
['Ñö']='Ñövä:BAAALgAECgEJAQAAAA==.',
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
