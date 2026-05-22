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

local lookup = {'Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Shaman-Restoration','Druid-Feral','Druid-Guardian','Rogue-Assassination','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Paladin-Retribution','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Priest-Discipline','Warlock-Demonology','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','Druid-Balance','Warrior-Protection','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Ader:BAAALgADCgkJDQAAAA==.',
Ae='Aeryhnn:BAAALgADCggJFwABLgAECgMJBQABAAAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8bAAICAAYJbxMvMwA2AQACAAYJbxMvMwA2AQAAAA==.Alexandre:BAABLgAECn8WAAIDAAcJTBLNWQA7AQADAAcJTBLNWQA7AQAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8WAAIEAAYJzg4rVAD5AAAEAAYJzg4rVAD5AAAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8hAAMCAAcJyxyLEQA+AgACAAcJyxyLEQA+AgAFAAMJ3QO1MgBPAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBQAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgEJAQAAAA==.',
Aq='Aquafresh:BAABLgAECn8oAAIGAAkJeBzgDQCXAgAGAAkJeBzgDQCXAgAAAA==.',
Ar='Arisel:BAABLgAECn8dAAMHAAcJkhI1EwAkAQAHAAYJzRI1EwAkAQAIAAQJOhIFHwCoAAABLgAECggJJQAJAKAOAA==.Aristia:BAAALgAECgMJAwAAAA==.Arweni:BAABLgAECn8uAAIKAAgJPxiVGgDKAQAKAAgJPxiVGgDKAQAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRDCADqAgACAAgJECRDCADqAgAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAQJDQAGAHALAA==.Avoidme:BAAALgADCgkJCQABLgAECgkJNQACANMdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgAECgEJAQABLgAECgkJNQACANMdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgQJBAABLgAECgYJEgABAAAAAA==.',
Be='Bearbacked:BAAALgADCggJCgABLgAECgEJAQABAAAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Belagrip:BAAALgAECgMJBAABLgAECgMJBQABAAAAAA==.Belashar:BAAALgAECgMJBQAAAA==.Beleron:BAAALgADCgMJAwAAAA==.Beytuha:BAABLgAECn8YAAIIAAgJSCKpBQBTAgAIAAgJSCKpBQBTAgAAAA==.',
Bi='Bigtim:BAAALgAECgYJCwAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAABLgAECn8YAAMLAAYJ/hxTWAB0AQALAAYJ/hxTWAB0AQAMAAQJlhQ7IgDrAAAAAA==.Blackknife:BAABLgAECn8uAAMNAAgJih7MCQA8AgANAAgJih7MCQA8AgAJAAEJGAkIIAAxAAAAAA==.Bladestorm:BAAALgAECgEJAQABLgAECgYJEgABAAAAAA==.Blakylightz:BAABLgAECn8fAAMFAAgJxxoECQBGAgAFAAgJxxoECQBGAgAOAAYJcwl5ugARAQABLgAFFAMJBAABAAAAAA==.Blinker:BAABLgAECn8eAAIPAAgJYww9fgA+AQAPAAgJYww9fgA+AQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAQJEAAPAD4YAA==.Blueberriess:BAAALgAECgEJAQAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEwABLgAFFAQJEwAEAKgHAA==.Bobbidyboo:BAACLgAFFH8TAAIEAAQJqAc9JADuAAAEAAQJqAc9JADuAAAuAAQKfy0AAgQACQlsFao2AM0BAAQACQlsFao2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJBwAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJDwAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgYJCAAAAA==.Brovar:BAACLgAFFH8RAAIOAAQJIh0qFQBoAQAOAAQJIh0qFQBoAQAuAAQKfyoAAw4ACAm1I3UaAMoCAA4ACAm1I3UaAMoCAAIABQlgCu1zAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAABLgAECn8hAAQQAAgJtw7VJQBcAQAQAAgJtw7VJQBcAQARAAQJ8QedOwCOAAASAAEJwwN9QwAoAAAAAA==.Bubblez:BAAALgAECgQJCQAAAA==.Buddydaelf:BAABLgAECn8fAAIDAAgJNheoNAC3AQADAAgJNheoNAC3AQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgADCgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Calithe:BAAALgAECgYJBgAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJEQABAAAAAA==.Castro:BAAALgADCgQJBAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.',
Ch='Chals:BAACLgAFFH8JAAMTAAQJ8h8OCwA5AQATAAMJ4iMOCwA5AQAUAAIJsA0WKACJAAAuAAQKfxYAAxMACAlIHygOAHkCABMABwn1HygOAHkCABQAAwkVGbA5ANkAAAEuAAUUBAkJABMA8h8A.Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chillfang:BAACLgAFFH8GAAILAAIJfQ2FmQCRAAALAAIJfQ2FmQCRAAAuAAQKfyMAAgsACAnPIaQ2AFwCAAsACAnPIaQ2AFwCAAAA.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgADCgMJAwAAAA==.',
Co='Connor:BAABLgAECn8pAAMUAAkJlxg/CgB6AgAUAAkJEBg/CgB6AgATAAEJgxefUwBBAAAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgcJEQAAAA==.',
Cr='Crosshair:BAAALgAECgQJCAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgADCgYJBgABAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Dacianwolf:BAAALgAECgUJAgAAAA==.Daemoni:BAAALgAECgYJCQAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJDgAAAA==.Darkerknight:BAAALgAECgQJBAAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgYJEgABAAAAAA==.Daveah:BAABLgAECn8dAAIGAAcJxhfHJADaAQAGAAcJxhfHJADaAQAAAA==.Dazarros:BAAALgAECgYJDwAAAA==.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8hAAIVAAgJ9Q2sYgCiAQAVAAgJ9Q2sYgCiAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgQJBgAAAA==.Demoncharge:BAAALgADCgcJBwABLgAECgcJDAABAAAAAA==.Demonclaw:BAAALgADCgMJAwABLgAECgcJDAABAAAAAA==.Demondrake:BAAALgAECgUJBwABLgAECgcJDAABAAAAAA==.Demonflayer:BAAALgAECgcJDAAAAA==.Demonicow:BAAALgAECgcJDQAAAA==.Demonikat:BAAALgADCgUJBQAAAA==.Denaeaa:BAABLgAECn8bAAIWAAgJLgyvLQA2AQAWAAgJLgyvLQA2AQABLgAFFAQJDQAGAHALAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgUJBQABLgAECgcJGAADAGIdAA==.',
Dh='Dhodge:BAABLgAECn8VAAIXAAYJ0SPwIwD4AQAXAAYJ0SPwIwD4AQABLgAFFAMJBQAYAJMcAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn81AAICAAkJ0x1PBgDpAgACAAkJ0x1PBgDpAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJCQAAAA==.',
Do='Doffyy:BAAALgAECgEJAQAAAA==.Dogbreathrlz:BAAALgADCgUJBQAAAA==.Dokash:BAAALgAECgMJBQABLgAECgUJDQABAAAAAA==.Dotexe:BAABLgAECn8WAAIJAAUJvB/yCwAqAQAJAAUJvB/yCwAqAQAAAA==.Dotsy:BAACLgAFFH8SAAQZAAQJNxiAAQBSAQAZAAQJ0haAAQBSAQAVAAMJFQ01VQDTAAAaAAEJFCDxFQBTAAAuAAQKfy0ABBoACQkJIq4PANMBABoABglDHK4PANMBABUABgkJIMVVAMYBABkABwnTIdsFALsBAAAA.',
Dr='Drackarys:BAAALgADCggJFAAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgMJBQAAAA==.Drakiir:BAAALgAECgQJCQABLgAECgYJEgABAAAAAA==.Dralkish:BAABLgAECn82AAIOAAkJLhPPSgCdAQAOAAkJLhPPSgCdAQAAAA==.Dramore:BAAALgAECgcJEgAAAA==.Drathi:BAAALgADCgcJBwABLgAECggJHQAOAD8fAA==.Dravas:BAAALgAECgUJDwAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Drezzo:BAAALgADCgMJAwAAAA==.Droxx:BAAALgAECgUJCgAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Dryerbro:BAAALgADCggJCwAAAA==.Drzark:BAAALgAECgMJBAAAAA==.',
Dw='Dwdog:BAABLgAECn8jAAIZAAkJrhg3AwAiAgAZAAkJrhg3AwAiAgAAAA==.',
['Dà']='Dàthguy:BAACLgAFFH8FAAILAAIJSyFhgQCmAAALAAIJSyFhgQCmAAAuAAQKfy8AAgsACQlWJXANAC4DAAsACQlWJXANAC4DAAAA.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJDwAAAA==.',
El='Elennie:BAAALgAECgEJAgAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elephlock:BAAALgAECgQJBAAAAA==.Elerion:BAABLgAECn8XAAIUAAgJdhVpFADhAQAUAAgJdhVpFADhAQAAAA==.Elista:BAAALgADCgUJBQABLgABCgcJBwABAAAAAA==.Elm:BAAALgADCgUJBQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgAAAA==.Emmi:BAABLgAECn8dAAILAAYJYxqdYwBWAQALAAYJYxqdYwBWAQAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIOAAcJ/B7jLwBjAgAOAAcJ/B7jLwBjAgAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8cAAMQAAgJYiL+BwD5AgAQAAgJDCL+BwD5AgASAAYJXSF4EQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJAwAAAA==.Fekk:BAAALgADCgIJAgAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn8dAAIMAAcJExztDQDVAQAMAAcJExztDQDVAQAAAA==.Fifthelement:BAABLgAECn8bAAIGAAcJrh70EwBYAgAGAAcJrh70EwBYAgAAAA==.',
Fj='Fjalgeirr:BAABLgAECn8cAAMbAAcJBxP1GgA+AQAbAAcJBxP1GgA+AQAcAAQJKAaBIQBGAAAAAA==.',
Fl='Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn8aAAITAAYJ8CLNDABNAgATAAYJ8CLNDABNAgAAAA==.',
Fr='Frey:BAACLgAFFH8SAAILAAQJICIYHgB+AQALAAQJICIYHgB+AQAuAAQKfzAAAgsACAl8JrcHAAMDAAsACAl8JrcHAAMDAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8aAAMZAAgJjSJZAQDjAgAZAAcJ7iRZAQDjAgAVAAUJaRzypAAOAQAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBQAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.',
Fw='Fwenwir:BAABLgAECn8YAAMdAAYJFSCWLADKAQAdAAYJfx+WLADKAQAeAAMJvxizLQDeAAAAAA==.',
Ga='Galatea:BAAALgADCgkJIQAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8bAAIKAAcJ6AspNQAkAQAKAAcJ6AspNQAkAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJFAABLgAECgcJIQACAMscAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gidgette:BAAALgAECgQJBQAAAA==.Gilalade:BAABLgAECn8cAAIDAAYJbxQUVgBmAQADAAYJbxQUVgBmAQAAAA==.',
Gl='Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8iAAILAAgJZgdwdAAxAQALAAgJZgdwdAAxAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECggJHAADAEobAA==.Gooby:BAAALgAECgQJBAABLgAFFAUJDwACAIMWAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgADCgMJAwAAAA==.Grimes:BAAALgAECgEJAQAAAA==.Grodin:BAAALgADCggJDwAAAA==.Grofiest:BAABLgAECn8YAAMfAAcJbhQsHQCGAQAfAAcJbhQsHQCGAQATAAEJjAHTYgAbAAAAAA==.',
Gu='Guggychan:BAACLgAFFH8FAAIYAAMJkxxgEADrAAAYAAMJkxxgEADrAAAuAAQKfzcAAhgACQl4JlEAAHUDABgACQl4JlEAAHUDAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIgAAkJTw9sGwCDAQAgAAkJTw9sGwCDAQAAAA==.Haelwyn:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.Haldor:BAABLgAECn8jAAIOAAgJewwaawBNAQAOAAgJewwaawBNAQAAAA==.Haohmaru:BAABLgAECn8dAAIhAAYJRR0OHwBwAQAhAAYJRR0OHwBwAQAAAA==.',
He='Hecæte:BAAALgADCgYJBgAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgMJBwAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIVAAUJ+RRjjQA+AQAVAAUJ+RRjjQA+AQAAAA==.',
Hi='Him:BAAALgADCgEJAQABLgAECggJLgAQADATAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.',
Hu='Hugeincanada:BAAALgAFFAEJAQAAAA==.Huneyhunter:BAAALgAECgQJDwAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
Im='Imsocold:BAAALgAFFAIJBAAAAA==.',
In='Intern:BAABLgAECn8ZAAQTAAYJaxi2HwB9AQATAAYJaxi2HwB9AQAUAAIJ8gpfTQBdAAAfAAEJAAD1cQAAAAAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgkJIAAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAABLgAECn8XAAISAAYJCA6JDQDuAAASAAYJCA6JDQDuAAAAAA==.Javeech:BAAALgAECgEJAgAAAA==.',
Jc='Jchaotic:BAAALgADCgYJBgAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAQJDAALAFEYAA==.',
Jo='Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwABAAAAAA==.',
Ju='Jutas:BAAALgAECgEJAQAAAA==.Juudaz:BAACLgAFFH8MAAILAAQJURgELQBYAQALAAQJURgELQBYAQAuAAQKfzIABAsACQlzIP8OALgCAAsACQkYH/8OALgCAAwABQkpIPIgADwBACIAAgn8CCsfAEEAAAAA.',
Jv='Jvicious:BAAALgAECgEJAQAAAA==.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8dAAMCAAYJKCP/EQA4AgACAAYJKCP/EQA4AgAOAAQJCxHspADjAAAAAA==.Kallan:BAAALgAECgUJDAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAAALgAECgcJDwABLgAECggJIAACABAkAA==.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.Katsumyo:BAAALgADCgUJBQAAAA==.',
Ke='Kegpoker:BAAALgAECgcJDwAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.',
Kh='Khaalzantro:BAAALgAECgIJAgAAAA==.',
Ki='Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJEgAAAA==.Kiyara:BAABLgAECn80AAIDAAgJuBU3LwDOAQADAAgJuBU3LwDOAQAAAA==.Kizaki:BAAALgADCgkJDgABLgAECgcJFQACAPkTAA==.',
Kn='Knowoone:BAABLgAECn8vAAIEAAgJZhb6JQDYAQAEAAgJZhb6JQDYAQAAAA==.',
Ko='Komonaut:BAAALgAECgMJAwAAAA==.Koscihardt:BAABLgAECn8VAAIPAAcJcwYQowD8AAAPAAcJcwYQowD8AAAAAA==.',
Kr='Krelliz:BAABLgAECn8cAAIGAAcJTBAWRwAuAQAGAAcJTBAWRwAuAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8bAAIPAAYJVwqMoQD+AAAPAAYJVwqMoQD+AAAAAA==.Krystar:BAAALgAECgQJCAAAAA==.',
Ku='Kulfig:BAAALgAECgcJDgAAAA==.Kumen:BAABLgAECn8cAAMjAAgJdx9wDABBAgAjAAgJjx1wDABBAgAIAAUJUxajGgD4AAAAAA==.Kungfuwho:BAACLgAFFH8JAAMgAAMJ0BMpHACUAAAgAAIJYxEpHACUAAAWAAIJLAKqLABdAAAuAAQKfzQAAyAACAkpGUcUAMcBACAACAkpGUcUAMcBABYABglwCpk8AOIAAAAA.Kutyou:BAAALgADCgMJAwAAAA==.',
['Kû']='Kûnei:BAAALgAECgQJBwAAAA==.',
La='Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8NAAIGAAQJcAtOMgC7AAAGAAQJcAtOMgC7AAAuAAQKfyQAAgYACAkEGx0jAAwCAAYACAkEGx0jAAwCAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAACLgAFFH8GAAICAAMJ5Q7IIADLAAACAAMJ5Q7IIADLAAAuAAQKfycAAgIACAkAFV4bANwBAAIACAkAFV4bANwBAAAA.Liiege:BAAALgAECgYJDwABLgAECgYJEgABAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgADCgkJFAAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJCAAAAA==.',
Lo='Lobø:BAABLgAECn8aAAIDAAcJ+Be+OACmAQADAAcJ+Be+OACmAQAAAA==.Loganx:BAAALgAECgIJAgAAAA==.Loxen:BAAALgADCgEJAQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8dAAILAAgJ0AfXcgA1AQALAAgJ0AfXcgA1AQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgQJBwAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgAECgEJAQAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAABLgAECn8WAAIPAAcJhQanlQATAQAPAAcJhQanlQATAQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgAECgEJAQAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAAALgAECgYJDgAAAA==.Manatee:BAAALgAECgYJCgAAAA==.Mannan:BAAALgADCgEJAQAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgcJCgAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Maygwyn:BAAALgAECgYJDgAAAA==.',
Me='Mediva:BAAALgADCgIJAgAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgUJCQAAAA==.Megaera:BAACLgAFFH8GAAIXAAMJwhvOIwCxAAAXAAMJwhvOIwCxAAAuAAQKfx4AAxcACQnuIPMOAAcDABcACQnuIPMOAAcDABsAAQkeGBZsADoAAAAA.Melar:BAABLgAECn8fAAMKAAcJTg3VMQA1AQAKAAcJTg3VMQA1AQAkAAEJWAC+UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.',
Mi='Mihawk:BAAALgAECgQJBwAAAA==.Milwaukee:BAAALgAECgEJAQAAAA==.Minjae:BAAALgAECgMJBQABLgAECggJLgAVAPYUAA==.Minseo:BAAALgAECgEJAgAAAA==.Miserain:BAAALgADCgIJAgAAAA==.Mistbehaving:BAAALgAECgEJAQAAAA==.Mistytouch:BAAALgADCgMJAwAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Morrìgan:BAAALgAECgYJEgAAAA==.Movack:BAABLgAECn8eAAIOAAgJUA4NXwBpAQAOAAgJUA4NXwBpAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.',
Mu='Muncha:BAAALgAECgEJAQAAAA==.Murderface:BAABLgAECn8XAAMEAAYJfBiQbAAOAQAEAAUJzBWQbAAOAQAjAAYJ5BU3LgANAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAABLgAECn8XAAIaAAcJaApfEADuAAAaAAcJaApfEADuAAAAAA==.Mythunran:BAABLgAECn8pAAIdAAgJXRJqCgB3AQAdAAgJXRJqCgB3AQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgMJAwAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAgAAAA==.Nerfhammer:BAACLgAFFH8QAAIOAAQJshm/HgBKAQAOAAQJshm/HgBKAQAuAAQKfyoAAg4ACQlIIwkcAMICAA4ACQlIIwkcAMICAAAA.Nessalove:BAACLgAFFH8UAAITAAQJoRECDwAJAQATAAQJoRECDwAJAQAuAAQKfysAAhMACQmUHTgMAI8CABMACQmUHTgMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8cAAQRAAgJqQ83GAAEAQARAAYJJxE3GAAEAQAQAAYJdw03OQDyAAASAAEJxANIQgArAAAAAA==.Nipao:BAAALgAECgMJBwABLgAECgYJDwABAAAAAA==.Niron:BAAALgAECgUJBwAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAAALgAFFAIJBAABLgAFFAcJIgAPAKokAA==.Noriel:BAAALgAECgYJDwAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAAALgAECgQJBAAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Og='Ognyal:BAAALgAECgkJBQAAAA==.',
Oh='Ohtani:BAAALgAECgcJDAAAAA==.',
Ol='Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn8sAAISAAgJsBC1BgCWAQASAAgJsBC1BgCWAQAAAA==.',
Or='Orfantal:BAABLgAECn8hAAIDAAkJExLWOQCiAQADAAkJExLWOQCiAQAAAA==.',
Ov='Oven:BAAALgAECgQJBAABLgAFFAIJBQALAEshAA==.Overcast:BAAALgAECgIJAwAAAA==.Overshoot:BAAALgAECgYJDgAAAA==.',
Ox='Oxen:BAAALgAECgUJBQAAAA==.',
Pa='Panterion:BAABLgAECn8UAAIEAAcJORUQPQBXAQAEAAcJORUQPQBXAQAAAA==.Parvarti:BAABLgAECn8XAAIaAAcJZgYWFADKAAAaAAcJZgYWFADKAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECggJDwABAAAAAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn8cAAIOAAcJPwxudAA5AQAOAAcJPwxudAA5AQAAAA==.Petthemonk:BAAALgADCgcJBQAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pigzox:BAAALgAECgQJBAAAAA==.Pinero:BAAALgADCgYJCQAAAA==.',
Pl='Plaugus:BAAALgADCgIJAgAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJEAAAAA==.Prost:BAAALgAECgcJEQAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Puppybreath:BAAALgAECgEJAQAAAA==.Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8QAAIPAAQJPhjCNwBJAQAPAAQJPhjCNwBJAQAuAAQKfzAAAg8ACAkZIR0hAO8CAA8ACAkZIR0hAO8CAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgADCgIJAgAAAA==.',
Re='Relaceara:BAABLgAECn8VAAIOAAgJgwUqjAANAQAOAAgJgwUqjAANAQAAAA==.Reladin:BAABLgAECn8dAAIFAAYJ+grzIQCvAAAFAAYJ+grzIQCvAAAAAA==.Relanna:BAAALgAECgYJEwAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCggJEwAAAA==.Rendstein:BAABLgAECn8WAAIMAAcJIhiTFABzAQAMAAcJIhiTFABzAQAAAA==.Renzr:BAACLgAFFH8FAAILAAIJyyOdbgDWAAALAAIJyyOdbgDWAAAuAAQKfz0AAwsACAmTJb4LANcCAAsACAkbJb4LANcCAAwABgmYIXIPAL4BAAAA.Reqquuiiem:BAAALgADCgUJCAAAAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ/INACAAQAEAAkJMQ/INACAAQAAAA==.Rowin:BAAALgAECggJDgAAAA==.',
Ru='Rustedroots:BAABLgAECn8ZAAIEAAcJ+xRELACvAQAEAAcJ+xRELACvAQAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgADCgEJAQAAAA==.Saltdisney:BAAALgADCgcJBwABLgAFFAYJEAACAKwKAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAABLgAECn8YAAIdAAgJjhEvCgB+AQAdAAgJjhEvCgB+AQAAAA==.Sarnara:BAABLgAECn8cAAIFAAcJZhmeDQCSAQAFAAcJZhmeDQCSAQABLgAECggJFQAXALAJAA==.Savagekegs:BAAALgAECgYJEwAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAABLgAECn8VAAIDAAYJ4ATAhADRAAADAAYJ4ATAhADRAAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgAECgEJAQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Senarx:BAAALgAECgEJAQAAAA==.Sereniity:BAAALgAECgYJEgAAAA==.',
Sh='Shamalicous:BAAALgAECgUJDwAAAA==.Shamjam:BAABLgAECn8VAAIGAAcJbBCnPABaAQAGAAcJbBCnPABaAQAAAA==.Shampayne:BAAALgADCgYJBgABLgAFFAQJDAALAFEYAA==.Shanthe:BAAALgAECgYJEQAAAA==.Sharku:BAABLgAECn8jAAIPAAgJSx/LJQBDAgAPAAgJSx/LJQBDAgAAAA==.Shãdo:BAAALgAECgIJAgAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECggJHAAQAGIiAA==.Siinep:BAAALgAECgcJEAAAAA==.',
Sk='Skibblé:BAAALgAECgcJBwAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAAALgAECgcJEAAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIXAAgJrSGCEgDrAgAXAAgJrSGCEgDrAgAAAA==.',
Sn='Sneakyboi:BAABLgAECn8uAAIJAAkJZxqvAgBjAgAJAAkJZxqvAgBjAgAAAA==.Snippin:BAAALgAECgEJAQAAAA==.',
So='Soléne:BAAALgAECgcJCgABLgAECgkJKwAVAGYgAA==.Sorden:BAAALgAECgQJBgAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIjAAgJSCC0DQDAAgAjAAgJSCC0DQDAAgABLgAECggJGgAZAI0iAA==.Spliff:BAAALgAECgEJAQAAAA==.',
Sq='Squirt:BAABLgAECn8aAAIRAAgJvQ88GgC6AQARAAgJvQ88GgC6AQAAAA==.',
Ss='Ssks:BAAALgAECgMJAwABLgAECgMJCwABAAAAAA==.',
St='Stabsmcshank:BAACLgAFFH8HAAINAAMJbgxgGwDeAAANAAMJbgxgGwDeAAAuAAQKfycAAg0ACQnNFVQUAKkBAA0ACQnNFVQUAKkBAAAA.Starbux:BAABLgAECn8dAAQUAAcJVxB6KwAbAQAUAAUJ7hB6KwAbAQATAAUJEA8/WgDLAAAfAAUJRwe4QQCwAAAAAA==.Steakx:BAAALgAECgQJBgAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAAALgAECgMJBQAAAA==.Suumcuique:BAAALgADCgMJAwABLgAECgYJFwAEAHwYAA==.',
Sv='Svenya:BAAALgAECgYJEgAAAA==.',
Sy='Sygne:BAAALgADCgYJBgAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn8dAAIDAAcJXwzgVABKAQADAAcJXwzgVABKAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJBwABLgAECggJFQAlADYTAA==.',
['Sï']='Sïenna:BAAALgAECgYJCAAAAA==.',
Ta='Taggy:BAABLgAECn8lAAIJAAgJoA4QCACEAQAJAAgJoA4QCACEAQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgADCggJCQABLgAECgcJFAAEADkVAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgAECgUJBQAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAcJFAAQALAaAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Thansus:BAAALgAECgEJAQAAAA==.Theçølletør:BAAALgAECgIJAgAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.Tinygibbs:BAAALgAECgMJAwAAAA==.',
To='Toiletnuker:BAAALgAECgYJEAABLgAECgkJNQACANMdAA==.Tokyojoe:BAABLgAECn8eAAIXAAkJsBSkJwDlAQAXAAkJsBSkJwDlAQAAAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8dAAQOAAgJPx/bHABWAgAOAAgJPx/bHABWAgACAAYJBRcRNwCfAQAFAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECggJHQAOAD8fAA==.Totemtot:BAABLgAECn8dAAImAAYJmwW0GAC+AAAmAAYJmwW0GAC+AAAAAA==.Toupee:BAAALgAECgEJAQAAAA==.',
Tr='Tradrivia:BAAALgADCggJGAAAAA==.Tronly:BAAALgADCgUJBQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Tw='Twinkish:BAAALgAECgEJAQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJCAAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJBwAAAA==.',
Ul='Ulf:BAAALgAECggJEAAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAABLgAECn8qAAIMAAcJvhmpEQCcAQAMAAcJvhmpEQCcAQAAAA==.Valyrius:BAAALgADCggJCQABLgAECgUJBQABAAAAAA==.Varlamor:BAAALgAECgcJEAAAAA==.Vathraen:BAAALgAECgMJAwAAAA==.',
Ve='Velanistra:BAABLgAECn8mAAIOAAgJ+A1VXgBqAQAOAAgJ+A1VXgBqAQAAAA==.Velanya:BAAALgADCgkJFQAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAABLgAECn8dAAIbAAcJXBCBHAAvAQAbAAcJXBCBHAAvAQAAAA==.Very:BAAALgAECgQJCAAAAA==.',
Vg='Vgerr:BAAALgAECgcJDgAAAA==.',
Vi='Viashino:BAAALgAECgEJAQABLgAECgIJAwABAAAAAA==.Vidarus:BAAALgAECgYJEwABLgAFFAQJEAAOALIZAA==.Viridian:BAAALgAECgMJBgABLgAFFAMJBgAXAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8cAAMDAAgJShtMPgCSAQADAAYJ1BtMPgCSAQAdAAYJlBfaEQD3AAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAAALgAFFAEJAQAAAA==.Vynos:BAABLgAECn8dAAIVAAcJ6QaFgQD5AAAVAAcJ6QaFgQD5AAAAAA==.Vysant:BAAALgADCgIJAgABLgAECgcJHQAVAOkGAA==.',
['Vä']='Väl:BAAALgAECgQJBwAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAABLgAECn8VAAMlAAgJNhOMMwATAQAlAAYJaxOMMwATAQAGAAUJ4BQQVgD0AAAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAECggJLQALAKYgAA==.Welkerdk:BAABLgAECn8tAAILAAgJpiA0GQBsAgALAAgJpiA0GQBsAgAAAA==.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAXAMIbAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECgQJBAAAAA==.',
Wo='Wolfman:BAABLgAECn8VAAIhAAgJyQX6NwDhAAAhAAgJyQX6NwDhAAAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAECgUJCgAAAA==.',
Xt='Xten:BAAALgAECgMJBQAAAA==.',
Ya='Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgUJCwAAAA==.',
Yo='Yoshinox:BAAALgAECgMJBAAAAA==.',
Za='Zalazam:BAABLgAECn8fAAIlAAgJyhsfEgAMAgAlAAgJyhsfEgAMAgAAAA==.Zalth:BAABLgAECn8dAAIPAAkJXwxlSwC2AQAPAAkJXwxlSwC2AQAAAA==.',
Ze='Zelliph:BAAALgAECgQJCAAAAA==.Zenagdrina:BAAALgAECgYJDAAAAA==.Zenobiå:BAAALgAECgcJDQAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAAALgAECgMJBQAAAA==.',
Zo='Zokor:BAAALgADCgkJIQAAAA==.Zorach:BAAALgAECgYJBgAAAA==.',
['Zá']='Zárá:BAABLgAECn8cAAIPAAYJmQ8UjgAhAQAPAAYJmQ8UjgAhAQAAAA==.',
['Ûn']='Ûncle:BAAALgADCgcJCwAAAA==.',
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
