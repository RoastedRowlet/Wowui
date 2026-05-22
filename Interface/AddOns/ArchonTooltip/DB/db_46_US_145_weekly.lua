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

local lookup = {'Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Paladin-Protection','Paladin-Retribution','Priest-Holy','Warlock-Demonology','Evoker-Devastation','Warlock-Affliction','Warlock-Destruction','Monk-Brewmaster','DeathKnight-Unholy','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Monk-Mistweaver','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Druid-Balance','Druid-Feral','Hunter-BeastMastery','Mage-Fire','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Unknown-Unknown','DemonHunter-Vengeance','Priest-Discipline','Warrior-Protection','Rogue-Assassination','Shaman-Elemental','Rogue-Subtlety','Shaman-Enhancement','Priest-Shadow','Warrior-Arms','Mage-Arcane','Rogue-Outlaw',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aahrya:BAAALgAFFAEJAQAAAA==.',
Ac='Ackreser:BAAALgAECgYJCgAAAA==.',
Ae='Aellana:BAAALgAECgEJAQAAAA==.Aevisea:BAABLgAECn8fAAIBAAgJLBTKTgCtAQABAAgJLBTKTgCtAQAAAA==.',
Ai='Aidan:BAECLgAFFH8hAAICAAcJwyY2AACrAgACAAcJwyY2AACrAgAuAAQKfx4AAgIACQkHJfkAAL8DAAIACQkHJfkAAL8DAAEuAAUUCQk6AAMAoCUA.Aidhan:BAECLgAFFH86AAIDAAkJoCUDAACUAwADAAkJoCUDAACUAwAuAAQKfy8AAwMACQnZJhQAAA4EAAMACQnZJhQAAA4EAAQABgmAEeU2ACsBAAAA.',
Aj='Ajanni:BAACLgAFFH8LAAIFAAQJaR50CAB0AQAFAAQJaR50CAB0AQAuAAQKfykAAgUACQlBIsoKAHMCAAUACQlBIsoKAHMCAAAA.',
Ak='Akamaki:BAAALgADCgMJBAAAAA==.',
Al='Alcore:BAAALgADCgMJAwAAAA==.Aldrigor:BAAALgAECgkJEQAAAA==.Alett:BAABLgAECn8VAAMGAAYJHQ5qHgDKAAAGAAYJHQ5qHgDKAAAHAAUJrwNc4ACEAAAAAA==.Alinni:BAAALgADCgkJHgAAAA==.Alivathus:BAACLgAFFH8OAAIIAAQJOia4AwDEAQAIAAQJOia4AwDEAQAuAAQKfzEAAggACQlkJXEBAHsDAAgACQlkJXEBAHsDAAAA.Alluring:BAAALgADCgcJBwAAAA==.Aloka:BAAALgAECgMJAwABLgAFFAUJCgAJABkRAA==.Alonzie:BAAALgADCgkJCQAAAA==.Alvart:BAAALgAECgYJBgAAAA==.',
Am='Amaru:BAAALgAECgEJAQAAAA==.Amateur:BAAALgADCgEJAQAAAA==.Amiko:BAAALgAECgQJCQAAAA==.',
An='Anaryll:BAAALgAECgEJAQAAAA==.Angriff:BAAALgAECgIJAwAAAA==.Anhedonia:BAAALgADCgMJAwAAAA==.Ansigar:BAAALgAECgYJDAAAAA==.',
Ap='Apep:BAABLgAECn8hAAIKAAgJ8xwYAwA0AgAKAAgJ8xwYAwA0AgAAAA==.',
Ar='Aramar:BAAALgADCgYJBwAAAA==.Arbark:BAACLgAFFH8VAAMLAAYJeR51AACuAQALAAUJ3iR1AACuAQAJAAYJexZMLQA1AQAuAAQKfx4ABAkACAnWJHgrAGECAAkABwlkJXgrAGECAAwABQkCINoSALUBAAsAAQkAANYlAFoAAAAA.Arbarkm:BAAALgADCgIJAgAAAA==.Arcelf:BAAALgAECgYJDAAAAA==.Arcnfrost:BAAALgAECgYJDgAAAA==.Ardone:BAAALgADCgkJEwAAAA==.Arenar:BAACLgAFFH8SAAMCAAUJUiW2AwCTAQACAAUJbCK2AwCTAQANAAMJIiLWFQApAQAuAAQKfyEAAwIACAmzIuULAL0CAAIABwm2I+ULAL0CAA0AAwkKHVZEALAAAAAA.Ariandralina:BAAALgAECgEJAQAAAA==.Arkham:BAAALgADCggJDgAAAA==.',
As='Ashaya:BAABLgAECn8UAAIOAAYJkQ94lgBTAQAOAAYJkQ94lgBTAQAAAA==.Ashenclaw:BAAALgAECggJDgAAAA==.Asmohdian:BAAALgAFFAIJAwAAAA==.Asra:BAACLgAFFH8KAAIJAAUJGRH5PAASAQAJAAUJGRH5PAASAQAuAAQKfzcABAkACAlBIy0PAJ4CAAkACAmQIS0PAJ4CAAsABgmaIN8GAOoBAAwAAwmVE4c1AOAAAAAA.',
Au='Auder:BAAALgADCgIJAgAAAA==.Aug:BAAALgADCgcJEwABLgAFFAUJEAAOALgdAA==.Auxevo:BAAALgAECgMJAwAAAA==.',
Av='Availl:BAAALgAECgQJBQAAAA==.Avinôx:BAACLgAFFH8WAAMPAAUJqBuJBwBkAQAPAAUJqBuJBwBkAQAQAAQJwhMgDwA6AQAuAAQKfyIAAxAACQlgJHgJAAoDABAACAmUI3gJAAoDAA8AAgn5I+kuANQAAAAA.',
Aw='Aweinon:BAAALgADCgkJCgAAAA==.',
Ay='Aydan:BAECLgAFFH8WAAQRAAUJiiRAAgB2AQAOAAQJxiN6GgCKAQARAAQJtyJAAgB2AQASAAEJAABcLwAAAAAuAAQKfx4AAw4ACQn5I1MJAFIDAA4ACQn5I1MJAFIDABIAAQk5Hss+AFUAAAEuAAUUCQk6AAMAoCUA.Aydin:BAEALgAFFAEJAQABLgAFFAkJOgADAKAlAA==.Aylan:BAAALgAECgQJBwAAAA==.',
Az='Aziera:BAAALgAECgQJCAABLgAECggJHwABACwUAA==.Azumaa:BAAALgAECgQJCAAAAA==.',
['Aù']='Aùra:BAAALgADCgQJBAAAAA==.',
Ba='Bacnmac:BAACLgAFFH8IAAIJAAQJiRTgPAASAQAJAAQJiRTgPAASAQAuAAQKfy8AAgkACAm9IEgXAMgCAAkACAm9IEgXAMgCAAAA.Bainironwind:BAAALgAECgYJCwAAAA==.Baiwushi:BAABLgAECn8hAAITAAkJ4x49BgDnAgATAAkJ4x49BgDnAgAAAA==.Bajablessed:BAAALgADCgEJAQAAAA==.Balavar:BAAALgADCgIJAgAAAA==.Baldyr:BAAALgADCgUJBwAAAA==.Balior:BAAALgAECgIJAgAAAA==.Balázs:BAAALgAECgcJDQAAAA==.Banksstt:BAAALgADCgEJAQAAAA==.Barly:BAAALgAECgEJAQAAAA==.',
Be='Bemba:BAAALgAECgMJBAAAAA==.Bench:BAAALgAECgEJAQABLgAFFAUJEQAUAOQYAA==.Bestricer:BAACLgAFFH8dAAIHAAgJPhc+AgA8AgAHAAgJPhc+AgA8AgAuAAQKfyMAAwcACQkWJjEBAHMDAAcACQkWJjEBAHMDABUAAgndFclWAH0AAAAA.',
Bi='Biggles:BAECLgAFFH8ZAAIWAAYJxxuHBQAdAgAWAAYJxxuHBQAdAgAuAAQKfx0ABBYACQm9HLklACICABYACQm9HLklACICABcABglNFRxAADEBABgAAQnyARg2AC0AAAAA.Bigred:BAABLgAECn8dAAMCAAkJOBAGFQC+AQACAAkJOBAGFQC+AQANAAYJ5wHpYAC+AAAAAA==.Bigshow:BAAALgAECgIJAgAAAA==.',
Bl='Blobney:BAACLgAFFH8dAAMJAAgJ+R+PAQArAgAJAAcJeyKPAQArAgAMAAQJGBxrBQAfAQAuAAQKfzwABAkACQmkJYcBALwDAAkACQmjJYcBALwDAAsABAlSJi4IAMkBAAwABAlKJU0VAJ8BAAAA.Bloodobot:BAAALgAECgQJDAAAAA==.Bloodymouth:BAABLgAECn8YAAMDAAgJXyM5GADEAgADAAgJISM5GADEAgAEAAYJwx/PIAC3AQAAAA==.Bluechip:BAABLgAECn8jAAIUAAgJyAziOQBnAQAUAAgJyAziOQBnAQAAAA==.Blueeagle:BAACLgAFFH8UAAMPAAUJ2iCeBQB2AQAPAAUJ2iCeBQB2AQAQAAIJliLtGADGAAAuAAQKfzkABBAACAnZJPMGACwDABAACAk+I/MGACwDAA8ABwmNJAEIAGQCABkAAQkAAMzKADsAAAAA.',
Br='Brandwon:BAABLgAECn8YAAIDAAYJWSLLPQD9AQADAAYJWSLLPQD9AQAAAA==.Braum:BAAALgAECgUJBwAAAA==.Brazlor:BAABLgAECn8fAAQJAAcJGhHNewAFAQAJAAYJdAzNewAFAQALAAEJOyLpJQBaAAAMAAIJqxOwLQA3AAAAAA==.Brikz:BAAALgAECggJDgAAAA==.Broboom:BAAALgAECgQJBAAAAA==.',
Bu='Bulletsponge:BAAALgADCgcJBwABLgAECgYJFQAZAMAYAA==.Butler:BAAALgAECgEJAQABLgAFFAQJCAADAAURAA==.Butterflyy:BAAALgAECgcJEAAAAA==.Butternutt:BAAALgADCgYJBwAAAA==.',
['Bä']='Bäddrägon:BAAALgAECggJEAAAAA==.',
Ca='Caelena:BAABLgAECn8gAAIZAAgJTwtdSgBpAQAZAAgJTwtdSgBpAQAAAA==.Callistra:BAAALgADCgMJAwAAAA==.Callmecrazy:BAAALgADCgQJBAAAAA==.Cameltoess:BAAALgAECgIJAgAAAA==.',
Ce='Celestial:BAACLgAFFH8GAAMLAAIJKAfSBgCRAAALAAIJKAfSBgCRAAAMAAEJ8AW+GwBDAAAuAAQKfzUABAwACAnLFkwMAP4BAAwACAnLFkwMAP4BAAsABQkaEhELAD4BAAkAAQljAJIzARgAAAAA.',
Ch='Charlíxcx:BAAALgAECgUJDgAAAA==.Chillice:BAACLgAFFH8IAAIBAAMJAhYdUwD/AAABAAMJAhYdUwD/AAAuAAQKfygAAwEACAnPIbkiAOgCAAEACAnPIbkiAOgCABoAAQkrE04MADsAAAAA.Chupacabra:BAAALgAECgYJEAAAAA==.Chuppa:BAAALgADCgEJAQAAAA==.Chuyz:BAABLgAECn8dAAIZAAgJyByVIQAPAgAZAAgJyByVIQAPAgAAAA==.Chuyzz:BAAALgAECgMJBQAAAA==.',
Ci='Cilelienea:BAAALgAECgUJDAAAAA==.Cinderion:BAAALgAECgYJCQAAAA==.',
Cl='Claymation:BAEALgAECgYJDwAAAA==.Clickchi:BAAALgAECgQJCwAAAA==.Clikclikboom:BAAALgAECgcJBQAAAA==.Cloudwarrior:BAAALgADCgEJAQABLgAFFAQJCwAUAKgfAA==.',
Co='Coin:BAAALgADCgcJCgAAAA==.Cordeliaa:BAABLgAECn9GAAIHAAkJkQ/ARACvAQAHAAkJkQ/ARACvAQAAAA==.Corkster:BAAALgADCgYJCAAAAA==.Coven:BAAALgAECgYJDgAAAA==.',
Cr='Crazyoldmage:BAAALgADCgUJBwAAAA==.Crendybby:BAAALgAECgMJAwAAAA==.Critfast:BAAALgAECgYJEwAAAA==.Crogh:BAAALgADCgIJAgAAAA==.Crunch:BAACLgAFFH8IAAIFAAMJGiHeGAAVAQAFAAMJGiHeGAAVAQAuAAQKfy8AAgUACQm3JKQEAOECAAUACQm3JKQEAOECAAAA.',
Cs='Cshaugh:BAAALgAECggJDwAAAA==.',
Cu='Cueballh:BAAALgADCgMJAwAAAA==.Curly:BAAALgAECgQJBwABLgAECggJGgAGAAAWAA==.Curlybonker:BAABLgAECn8aAAIGAAgJABaVDAD+AQAGAAgJABaVDAD+AQAAAA==.',
Cy='Cynikka:BAAALgADCgkJEAAAAA==.Cynthor:BAABLgAECn8kAAIbAAkJIgi8EABzAQAbAAkJIgi8EABzAQAAAA==.',
Da='Daboommonk:BAAALgAECgcJCQAAAA==.Dabz:BAABLgAECn8hAAMLAAgJqRsDBAAAAgALAAcJnRsDBAAAAgAMAAYJRhKiEQDfAAAAAA==.Daghahi:BAABLgAECn8uAAINAAkJgxiyDAAuAgANAAkJgxiyDAAuAgAAAA==.Dahyun:BAAALgADCgYJBgAAAA==.Daisharagos:BAABLgAECn8eAAIcAAgJJxnfFgDUAQAcAAgJJxnfFgDUAQAAAA==.Dalelor:BAABLgAECn8nAAUYAAgJjiJuBQC2AgAYAAgJziFuBQC2AgAWAAcJfyS4GwAgAgAdAAIJLCLDIADEAAAXAAIJLRcvTACEAAAAAA==.Dalethyr:BAAALgAECgUJCgAAAA==.Danley:BAAALgAECgIJAgAAAA==.Darthflamed:BAABLgAECn80AAMWAAgJcRFQQQCcAQAWAAgJcRFQQQCcAQAXAAcJ4Qs1OwBIAQAAAA==.Darthman:BAAALgADCgYJCwAAAA==.Davinah:BAABLgAECn8xAAIIAAkJyQ95GQC2AQAIAAkJyQ95GQC2AQAAAA==.Dawnara:BAAALgAECgUJDAAAAA==.',
De='Deathkick:BAABLgAECn8WAAMNAAYJfRAVOQDcAAANAAUJCA4VOQDcAAATAAIJPBBTXwBRAAAAAA==.Deathkwondo:BAAALgADCgMJAwAAAA==.Deleos:BAAALgAECgcJEAAAAA==.Delmus:BAAALgADCgkJGQABLgAECgYJDQAeAAAAAA==.Delphinae:BAABLgAECn8aAAIHAAcJNQlkggAfAQAHAAcJNQlkggAfAQAAAA==.Demitia:BAAALgADCgkJFgAAAA==.Demonated:BAAALgADCgEJAQAAAA==.Demonsponge:BAAALgADCggJCAABLgAECgcJFgAPAKklAA==.Derpalaherp:BAAALgADCgMJAwAAAA==.Devera:BAABLgAECn8cAAIXAAkJyg+jIgDoAQAXAAkJyg+jIgDoAQABLgAECgkJHQALALoSAA==.Devious:BAAALgADCgUJBAAAAA==.',
Dh='Dhae:BAAALgADCgMJAwAAAA==.Dhanydevito:BAAALgADCgQJBAAAAA==.',
Di='Dirtykahuna:BAAALgADCgMJAwABLgAECgYJGwAHAM0TAA==.Dirtypali:BAABLgAECn8bAAIHAAYJzRMLegAuAQAHAAYJzRMLegAuAQAAAA==.Dirtypoacher:BAAALgADCgEJAQABLgAECgYJGwAHAM0TAA==.Discodiyu:BAAALgAECgYJDAAAAA==.Disconnected:BAAALgAECgEJAQAAAA==.Disemboweler:BAAALgADCgcJEAAAAA==.Distress:BAAALgAECgYJDAAAAA==.',
Dm='Dmorte:BAAALgADCgkJCQAAAA==.',
Do='Dogtooth:BAAALgAECgUJBQAAAA==.Dojohunter:BAAALgAECgYJCwAAAA==.Doodman:BAEALgAECgEJAQABLgAECggJIwAdAA8XAA==.Doodmang:BAEBLgAECn8jAAIdAAgJDxfNDACpAQAdAAgJDxfNDACpAQAAAA==.Doozerdae:BAAALgADCgYJBwAAAA==.',
Dr='Dracrspurb:BAAALgADCgcJBQAAAA==.Dragondaddy:BAAALgAECgcJBwAAAA==.Dragondeez:BAAALgADCgUJBQABLgAECgkJJAAdACsiAA==.Dragonized:BAAALgADCgYJBgAAAA==.Droxigar:BAAALgAECgQJBgAAAA==.Drslay:BAAALgAECgQJBAAAAA==.Druhealer:BAAALgADCgUJBQAAAA==.Druidplowz:BAAALgADCgMJAgAAAA==.',
Du='Dumbclass:BAAALgADCgIJAgABLgAFFAgJHQAHAD4XAA==.Duty:BAABLgAECn8UAAMEAAYJnyKqDQDnAQAEAAYJnyKqDQDnAQAfAAIJdRSWIgBtAAAAAA==.',
Dw='Dwelknarr:BAAALgAECgYJDwAAAA==.',
['Dö']='Döminaria:BAAALgAECgIJAgAAAA==.',
Ea='Eadric:BAABLgAECn8vAAIHAAkJMyHyCwDRAgAHAAkJMyHyCwDRAgAAAA==.Earendur:BAAALgAECgQJCQAAAA==.Earthas:BAAALgAECgUJBQAAAA==.',
Ed='Edallen:BAABLgAECn8bAAIZAAgJdRbVNwCqAQAZAAgJdRbVNwCqAQAAAA==.',
Ei='Eightchaos:BAABLgAECn8fAAIEAAgJ7BAcFgBwAQAEAAgJ7BAcFgBwAQAAAA==.',
El='Elbrujo:BAAALgAECggJDAAAAA==.Eleaanor:BAABLgAECn8aAAMcAAgJCBUQIQC3AQAcAAgJCBUQIQC3AQAbAAgJ/QMsJQBOAQAAAA==.Eleana:BAAALgADCgcJBwABLgAECggJKAAgAHsdAA==.Elendra:BAAALgADCgIJAgAAAA==.Elontesla:BAAALgADCgMJAwAAAA==.',
Em='Emaytete:BAAALgAECgEJAQAAAA==.Empress:BAAALgAECgYJCwABLgAFFAcJGgASAHIkAA==.',
En='Entropius:BAABLgAECn8UAAIDAAcJ6Bi/NwCbAQADAAcJ6Bi/NwCbAQAAAA==.',
Er='Eratìc:BAAALgADCgkJCwAAAA==.',
Es='Esha:BAAALgADCgEJAQAAAA==.',
Et='Ethaerielle:BAAALgADCgIJAgAAAA==.',
Ev='Evillive:BAAALgAECgEJAQABLgAECgcJMQAhAMkVAA==.',
Ex='Exavin:BAAALgADCgYJBgAAAA==.',
Fa='Faezress:BAAALgAECgQJBQAAAA==.Faliss:BAAALgAFFAEJAQAAAA==.Falwyn:BAAALgAECgYJDQAAAA==.Famidore:BAAALgAECgQJBAAAAA==.Fancypantss:BAAALgADCgMJAwAAAA==.Fantasmina:BAAALgAECgQJBAAAAA==.',
Fe='Feargasma:BAAALgAECgQJBQABLgAECgYJGAAHAJ4HAA==.Felflamel:BAAALgAECgMJAwABLgAECggJNAAWAHERAA==.Felfook:BAAALgAECgYJEAAAAA==.Fellien:BAAALgAECgcJDQAAAA==.Feltest:BAABLgAECn8UAAIJAAgJeyP2CwC8AgAJAAgJeyP2CwC8AgAAAA==.Felystmagi:BAAALgADCgkJCgABLgAFFAIJBQAHAOoSAA==.Fengrey:BAABLgAECn8yAAMZAAgJnCJ7FgBWAgAZAAgJqSF7FgBWAgAQAAcJ4QtCQABZAQAAAA==.Feralized:BAAALgAECgQJBwAAAA==.Ferrenz:BAAALgAECgQJBAAAAA==.',
Fi='Fightmeqt:BAAALgADCgUJBQAAAA==.Fistenjoyer:BAABLgAECn85AAINAAkJsB8EBQC9AgANAAkJsB8EBQC9AgAAAA==.',
Fl='Flashter:BAAALgAECgIJAgAAAA==.Flaskdrunk:BAAALgAECgEJAQAAAA==.Flax:BAAALgAECgIJAwAAAA==.Flippincoco:BAACLgAFFH8FAAITAAMJdAXtIgCiAAATAAMJdAXtIgCiAAAuAAQKfysABBMACAmmF7oUACICABMACAmmF7oUACICAA0ACAlrClkuABEBAAIAAgnWCQh1AC8AAAAA.',
Fo='Foremancurly:BAAALgAECgQJBgABLgAECggJGgAGAAAWAA==.',
Fr='Franks:BAAALgAECggJEQAAAA==.Frayon:BAAALgAECgUJBQAAAA==.Froglord:BAAALgAECgUJBQAAAA==.Frozenhawk:BAAALgADCgMJAwAAAA==.',
Fy='Fynsty:BAABLgAECn8WAAICAAYJ6BWpLAAJAQACAAYJ6BWpLAAJAQAAAA==.',
Ga='Gaiah:BAAALgADCgEJAQAAAA==.Gaias:BAAALgAECgQJCgAAAA==.Galaesa:BAAALgADCgYJBgAAAA==.Galalea:BAAALgADCgYJCAAAAA==.Galdrel:BAAALgADCgYJBgAAAA==.Galdrial:BAAALgADCgMJAQAAAA==.Galeas:BAABLgAECn8hAAIVAAkJPx8pDAC6AgAVAAkJPx8pDAC6AgAAAA==.Galfurion:BAAALgAECgcJEAAAAA==.Galiniis:BAAALgADCgcJDQABLgAECgYJDQAeAAAAAA==.Gallarlyn:BAAALgADCgQJBAABLgAECgYJFwAVAJcVAA==.Gary:BAABLgAECn8hAAIUAAgJIST9AwA1AwAUAAgJIST9AwA1AwAAAA==.',
Ge='Geewilkr:BAABLgAECn8kAAIiAAgJ2wx0CAB6AQAiAAgJ2wx0CAB6AQAAAA==.Gerhart:BAABLgAECn8XAAIVAAYJnBNWLwBNAQAVAAYJnBNWLwBNAQAAAA==.',
Gh='Ghislaine:BAAALgAECgcJDgABLgAECgkJIQAVAD8fAA==.Ghostlegend:BAAALgADCgYJBgAAAA==.Ghostsham:BAACLgAFFH8sAAIjAAkJtSEKAABsAwAjAAkJtSEKAABsAwAuAAQKfzEAAiMACQn0JjEAAPoDACMACQn0JjEAAPoDAAAA.',
Gl='Glamizon:BAAALgAECgMJBgAAAA==.Glörfindel:BAAALgAECgcJBwAAAA==.',
Go='Goldoran:BAABLgAECn8eAAIFAAgJpRZhHQC0AQAFAAgJpRZhHQC0AQAAAA==.Goniff:BAACLgAFFH8GAAIGAAIJQSJsBgDJAAAGAAIJQSJsBgDJAAAuAAQKfzwAAwYACAmWJGcCABADAAYACAmWJGcCABADAAcACAmdGKovAPkBAAAA.Goransk:BAAALgAECgYJDAAAAA==.Gormash:BAAALgAECggJCgABLgAECggJDQAeAAAAAA==.Gorsk:BAAALgADCgkJEAABLgAECgYJDAAeAAAAAA==.',
Gr='Gracelious:BAABLgAECn8UAAMGAAUJxR1REgBJAQAGAAUJxR1REgBJAQAHAAQJhhItoQDpAAAAAA==.Graebrand:BAAALgAECgUJBQAAAA==.Graemyste:BAAALgAECgMJBwAAAA==.Graewynde:BAAALgADCgMJAwAAAA==.Grakkora:BAABLgAECn8rAAIZAAgJoiVpAgBzAwAZAAgJoiVpAgBzAwAAAA==.Grakkus:BAAALgADCgYJBgABLgAECggJKwAZAKIlAA==.Greffon:BAAALgADCgUJBQAAAA==.Greyshadow:BAABLgAECn8kAAIXAAgJLA0EJABOAQAXAAgJLA0EJABOAQAAAA==.Griffith:BAAALgAECgQJCgAAAA==.Grimreåper:BAAALgADCgcJCAAAAA==.Grotkal:BAAALgADCgcJBwAAAA==.Grubber:BAAALgAECgYJDwAAAA==.Grüb:BAAALgADCgcJDwABLgAECgYJDwAeAAAAAA==.',
Gu='Guitarbeef:BAAALgAECggJEwAAAA==.Guncarick:BAAALgAECgEJAQABLgAECggJJwAYAI4iAA==.Guntran:BAAALgAECgcJEAAAAA==.Gurthock:BAACLgAFFH8FAAIJAAMJLANXYAC1AAAJAAMJLANXYAC1AAAuAAQKfxUAAwkACAmEClGCAFYBAAkABwm+CFGCAFYBAAwABAlxCeY9AL0AAAAA.',
Gw='Gwenixx:BAAALgAECgQJCwAAAA==.',
Gy='Gymadin:BAAALgADCgEJAQAAAA==.',
['Gà']='Gàuron:BAAALgAECgYJDwAAAA==.',
['Gô']='Gôût:BAAALgADCgcJEwAAAA==.',
['Gû']='Gûnn:BAAALgADCgEJAgAAAA==.',
Ha='Hakke:BAAALgADCgMJAwAAAA==.',
He='Headhuntin:BAABLgAECn8kAAIZAAgJfBrBJQAkAgAZAAgJfBrBJQAkAgAAAA==.Hellgrammite:BAAALgADCgQJBAAAAA==.Hellione:BAAALgAECgMJAwAAAA==.Helltest:BAABLgAECn8jAAIDAAgJviW/BgBbAwADAAgJviW/BgBbAwAAAA==.Herraboosted:BAAALgAECgQJBQAAAA==.',
Hi='Hinari:BAAALgAECgQJBwABLgAECgYJFwAVAJcVAA==.Hiruzèn:BAAALgAECgQJCgAAAA==.',
Ho='Hoamanager:BAAALgAECgcJDwAAAA==.Hollowsoul:BAAALgADCgkJCQAAAA==.Holygrub:BAAALgADCgUJBQAAAA==.Holypwr:BAABLgAECn8vAAIHAAkJbiMiBgARAwAHAAkJbiMiBgARAwAAAA==.Hotdumpling:BAAALgAECgYJDgAAAA==.',
Hu='Huegarak:BAAALgAECgYJCwAAAA==.Huggybuns:BAAALgAECgEJAQAAAA==.',
Hy='Hyle:BAABLgAECn8cAAIhAAgJrgxOGQAgAQAhAAgJrgxOGQAgAQAAAA==.',
['Hø']='Høøds:BAAALgAECgkJBgAAAA==.',
Ic='Ichio:BAAALgADCgIJAwAAAA==.Icyvines:BAABLgAECn8XAAIRAAgJuBaYBgC8AQARAAgJuBaYBgC8AQAAAA==.',
Il='Ilidor:BAAALgAECgUJBQABLgAECgcJFQAkAKoPAA==.Illidanina:BAAALgAECgYJDwABLgAECggJFgABABENAA==.Illilando:BAAALgADCgMJAwAAAA==.Illuminator:BAAALgAECgQJCQAAAA==.',
In='Infntyonhigh:BAAALgADCgIJAgAAAA==.Inspectadeck:BAACLgAFFH8ZAAIJAAYJuwzDGgBxAQAJAAYJuwzDGgBxAQAuAAQKf0EAAwkACQkvH94JANUCAAkACQkvH94JANUCAAwABAltEjItAAkBAAAA.',
Ir='Ironson:BAAALgADCgYJBgAAAA==.Irsh:BAAALgADCggJCAAAAA==.',
Is='Istariel:BAACLgAFFH8HAAIJAAMJQxt/RAD8AAAJAAMJQxt/RAD8AAAuAAQKfxkAAwkACAldI5JOAHABAAkABwnYIpJOAHABAAwAAwk/IjxgAE4AAAEuAAUUCQksACMAtSEA.',
It='Ithoram:BAAALgADCgIJAgAAAA==.',
Iv='Ivoree:BAAALgADCgEJAQAAAA==.Ivoryson:BAAALgAECgIJAgAAAA==.',
Ja='Jacksparrowl:BAAALgAECgQJCAAAAA==.Jakarra:BAAALgAECgQJBAAAAA==.Jakesulli:BAAALgAECgEJAgAAAA==.Jalkymoose:BAAALgADCgQJBAAAAA==.Jaytov:BAAALgAECgIJAwAAAA==.Jazu:BAABLgAECn8gAAIBAAgJCSJIGACPAgABAAgJCSJIGACPAgAAAA==.',
Je='Jemba:BAABLgAECn8vAAIBAAkJfxojIgBXAgABAAkJfxojIgBXAgAAAA==.Jeras:BAAALgADCgIJAgAAAA==.Jerks:BAABLgAECn8yAAMlAAkJzxo9AwCMAgAlAAkJzxo9AwCMAgAUAAMJqQzKeQCrAAAAAA==.Jetblue:BAAALgADCggJDgABLgAECggJIwAUAMgMAA==.',
Ji='Jillidàn:BAAALgAECgMJAgAAAA==.Jinhala:BAAALgAECgYJDwABLgAFFAUJFAAPANogAA==.',
Jo='Joenips:BAABLgAECn8VAAMkAAcJqg8+KgCqAQAkAAcJSA0+KgCqAQAiAAQJZRO+EQDCAAAAAA==.Jokhan:BAAALgAECgQJBgAAAA==.Jorrell:BAABLgAECn8tAAIHAAkJphDJQAC8AQAHAAkJphDJQAC8AQAAAA==.Josh:BAACLgAFFH8MAAIDAAQJUhhPHgBPAQADAAQJUhhPHgBPAQAuAAQKfyQAAgMACAn2HQAcAKoCAAMACAn2HQAcAKoCAAAA.Jotun:BAAALgAECgEJAgABLgAECgIJCAAeAAAAAA==.Joval:BAAALgAECgQJCwAAAA==.Jozeph:BAABLgAECn8lAAIRAAkJXCB1AQDoAgARAAkJXCB1AQDoAgAAAA==.',
Ju='Juno:BAAALgADCgYJDgAAAA==.',
['Jà']='Jàmie:BAAALgAECggJEAAAAA==.',
Ka='Kaalar:BAABLgAECn8nAAIZAAkJnx4ZFwBRAgAZAAkJnx4ZFwBRAgAAAA==.Kaestirael:BAAALgAECgYJEwAAAA==.Kakarót:BAAALgADCgkJCQAAAA==.Kalmia:BAABLgAECn8lAAIXAAgJoheKEwDjAQAXAAgJoheKEwDjAQAAAA==.Kamoura:BAABLgAECn8uAAIBAAkJlhr0IABdAgABAAkJlhr0IABdAgAAAA==.Kapeta:BAABLgAECn8YAAIDAAgJSRz4HAAiAgADAAgJSRz4HAAiAgAAAA==.Karmen:BAACLgAFFH8ZAAIbAAYJKySfAgBLAgAbAAYJKySfAgBLAgAuAAQKfx0AAhsACQnvJYIBAG8DABsACQnvJYIBAG8DAAAA.Karnara:BAAALgADCgcJCQABLgAECgQJCwAeAAAAAA==.Karnatron:BAAALgAECgQJCwAAAA==.Kassassasass:BAAALgAECgEJAQABLgAFFAkJJwADALchAA==.Kayha:BAAALgADCgEJAQAAAA==.Kayleave:BAACLgAFFH8TAAImAAYJQw+9DgBDAQAmAAYJQw+9DgBDAQAuAAQKfyMAAiYACQlpHgINALMCACYACQlpHgINALMCAAAA.Kazuha:BAAALgADCgkJGAABLgAECgkJOwAWAFkZAA==.Kazz:BAABLgAECn87AAIWAAkJWRlODwCXAgAWAAkJWRlODwCXAgAAAA==.',
Ke='Kealohalani:BAAALgAECgEJAQAAAA==.Keattz:BAABLgAFFH8HAAMFAAMJDBbJFQC3AAAFAAIJNh3JFQC3AAAnAAIJRxAIDABSAAABLgAFFAYJGwAkAPkgAA==.Keattzdh:BAABLgAFFH8KAAIDAAUJHhF5LAAgAQADAAUJHhF5LAAgAQABLgAFFAYJGwAkAPkgAA==.Keattzdx:BAABLgAECn8VAAIkAAcJyCJjHQAUAgAkAAcJyCJjHQAUAgABLgAFFAYJGwAkAPkgAA==.Keattzxd:BAACLgAFFH8bAAMkAAYJ+SDIAgD1AQAkAAYJ+SDIAgD1AQAiAAIJ7hdWAwDFAAAuAAQKfysAAyQACAk3I8IEAEoDACQACAk3I8IEAEoDACIAAQmfIScZAGUAAAAA.Keatzz:BAABLgAFFH8PAAMOAAUJ3BudOgBBAQAOAAQJ3BudOgBBAQASAAEJAAD8PQAAAAABLgAFFAYJGwAkAPkgAA==.Keedill:BAABLgAECn8hAAMJAAgJdBTXOwCsAQAJAAgJdBTXOwCsAQAMAAEJAAB+QAAAAAAAAA==.Keelinnea:BAAALgADCgcJDwAAAA==.Keelu:BAAALgADCgEJAQAAAA==.Keggerz:BAAALgAECgYJDAAAAA==.Kelii:BAABLgAFFH8GAAITAAQJPAYqDgC8AAATAAQJPAYqDgC8AAABLgAFFAUJEQAUAOQYAA==.Kennagi:BAAALgAECgIJAgAAAA==.Kenshunterl:BAABLgAECn8bAAIZAAcJrgkVXgAvAQAZAAcJrgkVXgAvAQAAAA==.',
Kh='Kharka:BAABLgAECn8XAAMJAAgJMSNHGQC9AgAJAAgJMSNHGQC9AgALAAEJAAC4KwBHAAAAAA==.Khathgar:BAAALgADCggJEgABLgAECggJNgAYAOQeAA==.Khomorphisis:BAABLgAFFH8FAAIDAAIJfwZvXgB+AAADAAIJfwZvXgB+AAABLgAFFAYJGAAYABIeAA==.Khovastis:BAACLgAFFH8YAAMYAAYJEh6MAADOAQAYAAUJRByMAADOAQAXAAEJSCXXLABqAAAuAAQKfyMAAxgACQnLI0sDAAUDABgACQkjIksDAAUDABcABQmgGWcrAB4BAAAA.',
Ki='Kianll:BAAALgAECgMJBAAAAA==.Kiljorith:BAABLgAECn8kAAIgAAgJEgRRKgAiAQAgAAgJEgRRKgAiAQAAAA==.Kiralnikika:BAAALgAECgMJAwAAAA==.Kiron:BAAALgADCgMJAwAAAA==.Kiros:BAAALgAECgYJDwAAAA==.Kitchntabls:BAACLgAFFH8TAAMDAAYJURY+DgCuAQADAAYJURY+DgCuAQAEAAEJ9AgDDgBOAAAuAAQKfxwAAwMACQkiHngqAFcCAAMACQltHHgqAFcCAAQABwnXGZcaAO4BAAAA.',
Kj='Kjdoublehey:BAAALgAECgMJBAAAAA==.Kjinthal:BAABLgAECn8hAAMcAAgJCh52DwAnAgAcAAgJnB12DwAnAgAKAAYJox0KDwDrAQAAAA==.',
Kl='Kleno:BAAALgAECgcJBwAAAA==.',
Ko='Koenji:BAACLgAFFH8WAAIlAAYJtRWmAQCLAQAlAAYJtRWmAQCLAQAuAAQKfxwAAiUACAkFIYoEANECACUACAkFIYoEANECAAAA.Korastos:BAAALgAECgIJAgABLgAECggJKAAgAHsdAA==.Korastus:BAABLgAECn8oAAMgAAgJex2/DQA7AgAgAAgJ6Rm/DQA7AgAIAAcJ0Rk9HQD0AQAAAA==.Korvaany:BAABLgAECn8hAAIkAAkJXxdXDwDnAQAkAAkJXxdXDwDnAQAAAA==.',
Kp='Kpc:BAAALgAECgIJAwABLgAFFAMJBQABAL8KAA==.Kpcmini:BAACLgAFFH8FAAIBAAMJvwoIXQDpAAABAAMJvwoIXQDpAAAuAAQKfykAAgEACAlZGuRLAFMCAAEACAlZGuRLAFMCAAAA.Kpcmoose:BAAALgADCgEJAQABLgAFFAMJBQABAL8KAA==.',
Kr='Krinne:BAACLgAFFH8HAAIWAAQJkhKGHgAQAQAWAAQJkhKGHgAQAQAuAAQKfygAAhYACAl3JDAHABkDABYACAl3JDAHABkDAAAA.Krizez:BAAALgAECgYJDAAAAA==.',
Ky='Kyndas:BAAALgADCgQJBAAAAA==.Kyndel:BAACLgAFFH8NAAIlAAUJOBMNBAA9AQAlAAUJOBMNBAA9AQAuAAQKfyAAAiUABwm/Gd4KACACACUABwm/Gd4KACACAAAA.',
['Kä']='Käne:BAABLgAECn8WAAIOAAcJlxUMZwBOAQAOAAcJlxUMZwBOAQAAAA==.',
['Kí']='Kín:BAAALgAECgQJCAABLgAECgkJFwAdAA8VAA==.',
La='Lableue:BAAALgADCgYJBgAAAA==.Lalada:BAEALgAECgUJBQAAAA==.',
Le='Legateflame:BAAALgADCgYJBgAAAA==.Legendáry:BAABLgAECn8WAAIBAAgJEQ3qsAB7AQABAAgJEQ3qsAB7AQAAAA==.Legimp:BAABLgAECn8oAAIcAAkJOxITGwCtAQAcAAkJOxITGwCtAQAAAA==.Lehvy:BAABLgAECn8nAAIIAAgJ2xZ9EgD/AQAIAAgJ2xZ9EgD/AQAAAA==.Lerann:BAABLgAECn8cAAIDAAgJ7h/ZFABbAgADAAgJ7h/ZFABbAgAAAA==.Levey:BAAALgADCggJCAABLgAECggJJwAIANsWAA==.Leylla:BAAALgAECgUJBQABLgAECgYJDwAeAAAAAA==.',
Li='Libi:BAAALgADCgUJBQAAAA==.Lict:BAACLgAFFH8KAAIVAAQJows5JwCXAAAVAAQJows5JwCXAAAuAAQKfy8AAhUACAlHHRsUAHICABUACAlHHRsUAHICAAEuAAQKBwkIAB4AAAAA.Lightbearer:BAAALgADCgIJAgAAAA==.Lightninghan:BAAALgADCggJCwAAAA==.Lilithene:BAAALgAECgYJEwABLgAFFAUJCgAJABkRAA==.Lillea:BAABLgAECn8lAAIIAAgJMQ7ZJQBNAQAIAAgJMQ7ZJQBNAQAAAA==.Lissiria:BAAALgAECggJCAABLgAECgcJFgAYAMAaAA==.Litebringer:BAABLgAECn8WAAIVAAgJdwrPKwBkAQAVAAgJdwrPKwBkAQAAAA==.Lizardwizard:BAAALgAECgQJCgAAAA==.',
Lo='Loktalaan:BAACLgAFFH8bAAIlAAYJHRYXAQCoAQAlAAYJHRYXAQCoAQAuAAQKfz8AAiUACQnJJJgAADUDACUACQnJJJgAADUDAAAA.Lonjurace:BAAALgAECgIJAgAAAA==.Lorathis:BAAALgAECgcJBwAAAA==.',
Lu='Luan:BAACLgAFFH8FAAIFAAMJaAizJADKAAAFAAMJaAizJADKAAAuAAQKfyUAAwUACQl+Fb8XAOMBAAUACQnLFL8XAOMBACEAAwnZGuAuAMwAAAAA.Lucien:BAABLgAECn87AAIWAAgJhhlkIQA6AgAWAAgJhhlkIQA6AgAAAA==.Luni:BAABLgAECn8jAAIUAAgJNBCAKwCyAQAUAAgJNBCAKwCyAQAAAA==.Lute:BAABLgAECn8iAAMUAAgJlxmoIgDmAQAUAAgJlxmoIgDmAQAjAAIJMBsGVQCNAAAAAA==.',
Ly='Lycha:BAAALgAECgYJEwAAAA==.Lyfeguard:BAABLgAECn8dAAMIAAgJHx53DQBEAgAIAAcJ+x93DQBEAgAgAAMJRRclOADGAAAAAA==.Lyridrael:BAAALgAECgEJAQAAAA==.',
Ma='Mahito:BAAALgAECgYJDwABLgAECgkJOwAWAFkZAA==.Maleus:BAAALgADCgEJAQAAAA==.Malianas:BAAALgADCgUJCgAAAA==.Malitax:BAABLgAECn8fAAIBAAYJ/QsvlQAUAQABAAYJ/QsvlQAUAQAAAA==.Malzah:BAAALgADCgQJBAAAAA==.Manaless:BAACLgAFFH8MAAIBAAQJ2RW5OQBGAQABAAQJ2RW5OQBGAQAuAAQKfycAAwEACAn2Is8YABYDAAEACAn2Is8YABYDACgAAQmJCwIfADIAAAEuAAUUBAkIAA4AahoA.Manawarrx:BAABLgAECn8YAAImAAgJWyU2BABTAwAmAAgJWyU2BABTAwAAAA==.Marderer:BAABLgAECn8lAAIiAAgJMA/uBwCHAQAiAAgJMA/uBwCHAQAAAA==.Mariene:BAAALgADCgYJCAABLgAECggJHwABACwUAA==.Mariuss:BAAALgAECgUJBQABLgAFFAYJGAABAGAbAA==.Marizio:BAAALgAECgEJAgAAAA==.Masakari:BAABLgAECn8nAAIZAAkJ3xQ5IwAHAgAZAAkJ3xQ5IwAHAgAAAA==.Matahari:BAAALgADCgEJAQAAAA==.Mattðaemon:BAAALgADCgMJAwAAAA==.Mazz:BAAALgAECgIJAgABLgAECgcJFgAMAPkXAA==.Mazzlock:BAABLgAECn8WAAMMAAcJ+RdzCAB1AQAMAAYJVxtzCAB1AQAJAAQJYA6IkgDYAAAAAA==.',
Mc='Mcgyvr:BAABLgAECn8aAAIPAAcJRxG5GgB9AQAPAAcJRxG5GgB9AQAAAA==.',
Me='Mealo:BAAALgADCgQJBAAAAA==.Megameow:BAABLgAECn82AAIYAAgJ5B44BABwAgAYAAgJ5B44BABwAgAAAA==.Mercuria:BAAALgAECgQJBgAAAA==.Meriel:BAAALgADCgYJCgAAAA==.',
Mh='Mherlen:BAABLgAECn8qAAMBAAkJnyIgFgCcAgABAAkJnyIgFgCcAgAoAAEJuxucGwA9AAAAAA==.',
Mi='Miriane:BAAALgAECgIJAwAAAA==.Misile:BAAALgADCgEJAQAAAA==.Missmonk:BAAALgADCgcJEwABLgAECgYJDQAeAAAAAA==.Mistystepbro:BAAALgADCgMJAwAAAA==.Mitrixx:BAAALgAECgcJBwAAAA==.Mitsuri:BAAALgADCgcJBwABLgAECgYJDQAeAAAAAA==.',
Mo='Mobius:BAAALgAECgEJAQAAAA==.Mobro:BAAALgADCggJFQAAAA==.Mokuo:BAABLgAFFH8KAAMFAAUJthXPCABjAQAFAAQJmBrPCABjAQAnAAEJLwKXJABBAAAAAA==.Mongöose:BAAALgADCgQJBAAAAA==.Moni:BAAALgAECgYJDAAAAA==.Monkmommy:BAAALgAECgQJCQAAAA==.Monkzy:BAAALgAECgIJAwAAAA==.Moomedic:BAAALgAECgYJDAAAAA==.Moondrius:BAABLgAECn84AAUXAAkJfR1wFQDPAQAXAAcJVB5wFQDPAQAYAAYJnh0TCwCrAQAWAAgJCxXHPwCjAQAdAAEJ9xOTPgA4AAAAAA==.Moonthorn:BAABLgAECn8fAAICAAcJqQwqKAAkAQACAAcJqQwqKAAkAQAAAA==.Mort:BAABLgAECn8cAAIfAAcJEBICDABBAQAfAAcJEBICDABBAQAAAA==.Moxou:BAAALgAECgQJBQAAAA==.Moxxou:BAACLgAFFH8QAAIUAAMJbB/mHgARAQAUAAMJbB/mHgARAQAuAAQKfzQAAhQACQlJITcHAPQCABQACQlJITcHAPQCAAAA.Moxxoufanboy:BAAALgAFFAMJAwAAAA==.',
Mu='Mulch:BAACLgAFFH8GAAIWAAIJFQXmQwBrAAAWAAIJFQXmQwBrAAAuAAQKfzkAAhYACAmyFVIhAPcBABYACAmyFVIhAPcBAAAA.Murciélago:BAAALgADCgEJAQAAAA==.Murray:BAAALgAECgIJAgAAAA==.',
My='Mybelle:BAABLgAECn8cAAIZAAcJRwwsYwAiAQAZAAcJRwwsYwAiAQAAAA==.Mysticle:BAAALgAECgMJBQAAAA==.Mythaltis:BAABLgAECn8nAAIEAAgJTCS3BACyAgAEAAgJTCS3BACyAgAAAA==.',
Na='Narache:BAAALgAECggJDQAAAA==.Naul:BAAALgAECgYJCgABLgAFFAMJBQAFAGgIAA==.Naur:BAAALgADCgMJAwABLgAFFAMJBQAFAGgIAA==.',
Ne='Necrokai:BAABLgAECn8oAAQWAAgJrh4iEwCcAgAWAAgJrh4iEwCcAgAdAAUJzh8SEQBmAQAXAAYJPxZ4JwA3AQAAAA==.Neighter:BAAALgAECgQJBAAAAA==.Nerevar:BAAALgAECgQJBwAAAA==.Netal:BAAALgAECgUJBgAAAA==.Netherbear:BAEALgAECgYJDAAAAA==.Nethermonk:BAEALgAECgYJCwABLgAECgYJDAAeAAAAAA==.Netherrage:BAEALgAECgQJBAABLgAECgYJDAAeAAAAAA==.Nezhul:BAAALgAECgkJEwAAAA==.',
Ni='Nikehalo:BAAALgAECgkJBwAAAA==.Ninejuanjuan:BAABLgAECn8ZAAIVAAgJ5RQ4HQDNAQAVAAgJ5RQ4HQDNAQAAAA==.',
No='No:BAACLgAFFH8WAAIHAAYJLyGhBQDfAQAHAAYJLyGhBQDfAQAuAAQKfxwAAgcACAnCI4kRAAUDAAcACAnCI4kRAAUDAAAA.Nochit:BAAALgADCggJCAABLgAECggJGAAmAFslAA==.Noctula:BAABLgAECn8UAAMLAAcJoxkjDQAaAQAJAAcJhRVpYABBAQALAAQJ6RgjDQAaAQABLgAECggJKAAWAK4eAA==.Norne:BAABLgAECn8mAAIEAAkJ6B3SBACvAgAEAAkJ6B3SBACvAgAAAA==.Nozok:BAAALgAECgQJCgAAAA==.',
Ny='Nysera:BAAALgAECgYJCgAAAA==.Nytkiller:BAAALgAECgIJAgAAAA==.Nyxy:BAAALgAECgEJAQAAAA==.Nyzul:BAAALgAECgYJDQAAAA==.',
Oa='Oakherst:BAAALgADCgMJAwAAAA==.',
Od='Odlinn:BAAALgAECgQJBAABLgAFFAIJBgAWABUFAA==.',
Oo='Ooljee:BAAALgADCgMJAwABLgAECgkJLgANAIMYAA==.',
Op='Opallea:BAAALgAECgYJDQAAAA==.Oppa:BAAALgADCgkJCQABLgAECgYJDQAeAAAAAA==.',
Or='Oriazure:BAAALgADCgcJBwAAAA==.',
Ov='Overclocked:BAABLgAECn8sAAIJAAkJEQ7IOQCzAQAJAAkJEQ7IOQCzAQAAAA==.Ovid:BAAALgAECgUJCwAAAA==.',
Pa='Paddington:BAABLgAECn8oAAIdAAkJCw3mFAA1AQAdAAkJCw3mFAA1AQAAAA==.Pahbi:BAAALgAECgQJCwAAAA==.Palempi:BAAALgADCgcJCwAAAA==.Pastorjohn:BAAALgAECgUJBQAAAA==.',
Pe='Pendojight:BAAALgAECggJEAAAAA==.Pendojo:BAACLgAFFH8LAAIHAAQJbiRVCwCdAQAHAAQJbiRVCwCdAQAuAAQKfxUAAgcACAmnIwYPABYDAAcACAmnIwYPABYDAAAA.Pendomage:BAAALgAECgEJAgAAAA==.Pendovoker:BAAALgAECgEJAQAAAA==.',
Ph='Phidias:BAAALgAECgEJAQAAAA==.Phister:BAAALgADCgIJAgAAAA==.Phorne:BAAALgADCgEJAQAAAA==.',
Pi='Pifchi:BAAALgAECgEJAgAAAA==.Pifril:BAAALgAECgEJAwAAAA==.Pifs:BAAALgADCgYJCAAAAA==.Pinay:BAAALgAECgQJBAAAAA==.Pip:BAABLgAECn8lAAMjAAkJ2BnFIAAJAgAjAAgJxhjFIAAJAgAUAAMJygRdgQCOAAABLgAECgkJHQALALoSAA==.Pipium:BAABLgAECn8dAAILAAkJuhLEBAAqAgALAAkJuhLEBAAqAgAAAA==.',
Pl='Plagued:BAAALgAECgEJAgAAAA==.',
Po='Pocketpotion:BAAALgAECgcJCwAAAA==.Poisun:BAAALgAECgUJDwAAAA==.Pookiehandz:BAABLgAECn8YAAISAAkJZRZEDADyAQASAAkJZRZEDADyAQAAAA==.Pookiemonstr:BAAALgAECgYJEgAAAA==.Porpul:BAAALgAECggJDAAAAA==.Powery:BAAALgAECgEJAQAAAA==.',
Pr='Prizrak:BAAALgAECgYJBgABLgAFFAkJLAAjALUhAA==.Project:BAAALgAECgUJDAAAAA==.',
Ps='Psychoticvet:BAAALgAECgYJCAAAAA==.',
Pu='Punchyheal:BAAALgAECgIJAwAAAA==.Punkinpie:BAAALgAECgMJBAAAAA==.Purple:BAAALgADCgYJBgABLgAECggJGQAZANMfAA==.Purples:BAABLgAECn8ZAAMZAAgJ0x+9DgDFAgAZAAgJ0x+9DgDFAgAQAAEJRQyXjQAtAAAAAA==.Purppally:BAAALgADCgUJCAAAAA==.Purrplerain:BAABLgAECn8kAAMdAAkJKyLaBQBMAgAdAAgJXh7aBQBMAgAXAAkJZiDqCwBJAgAAAA==.',
['Pà']='Pàarthurnax:BAAALgAECgQJBAAAAA==.',
['Pá']='Páïnful:BAAALgADCggJEQAAAA==.',
Qu='Quellyana:BAAALgADCgYJBgAAAA==.',
Ra='Radicalfire:BAAALgADCgMJAwAAAA==.Rags:BAAALgADCgUJBQAAAA==.Rahios:BAAALgAECgEJAQAAAA==.Raikeji:BAAALgAECgIJAgABLgAECggJHAADAO4fAA==.Rainan:BAAALgAECgEJAQAAAA==.Raisins:BAACLgAFFH8YAAIVAAYJtyCRAQD5AQAVAAYJtyCRAQD5AQAuAAQKfyYAAxUACQnfIrEDADcDABUACAllI7EDADcDAAcABQknErm5ABIBAAAA.Raisyns:BAAALgAECgkJBwABLgAFFAYJGAAVALcgAA==.Ramune:BAAALgADCgEJAQAAAA==.Ranal:BAAALgADCgUJBQABLgAECgQJBwAeAAAAAA==.Raptorguin:BAABLgAECn8bAAMEAAgJpSRBBAC+AgAEAAgJkyNBBAC+AgADAAUJ3yMVMgCzAQAAAA==.Raulothim:BAABLgAECn8fAAMgAAgJYxnHEwDpAQAgAAgJORjHEwDpAQAIAAYJFAnFVwDWAAAAAA==.',
Re='Retribussy:BAABLgAECn8dAAIHAAYJyx9/PwC/AQAHAAYJyx9/PwC/AQAAAA==.Rezmir:BAAALgADCgQJBAAAAA==.',
Ri='Ricemachinex:BAABLgAECn8WAAMJAAcJuRmolgDQAAAJAAcJuRmolgDQAAAMAAIJdxu+SQCRAAABLgAFFAgJHQAHAD4XAA==.Ricemachnedk:BAACLgAFFH8QAAIOAAQJbR5jHQCAAQAOAAQJbR5jHQCAAQAuAAQKfyAAAw4ACAnTJTwfAMYCAA4ABwl3JjwfAMYCABEABQnjIYIbAF4AAAEuAAUUCAkdAAcAPhcA.Ricos:BAAALgAECgQJDwAAAA==.Rizokenn:BAAALgAECgkJEgAAAA==.',
Ro='Roan:BAAALgAECgIJCAAAAA==.Rockky:BAAALgADCgYJBgAAAA==.Rocthar:BAABLgAECn8qAAMHAAkJ0xwxJgAiAgAHAAkJ0xwxJgAiAgAVAAIJNxeUVACIAAAAAA==.Romeoposter:BAAALgAECgYJDwAAAA==.Rotandroll:BAABLgAFFH8GAAIOAAMJHRZDVwABAQAOAAMJHRZDVwABAQAAAA==.Roundhouse:BAAALgAECgQJBwAAAA==.Rovak:BAAALgADCgYJCQAAAA==.',
Ru='Rukarazyll:BAAALgADCgcJCwABLgADCgcJEAAeAAAAAA==.Ruush:BAABLgAECn8WAAMHAAcJex03UwCGAQAHAAcJex03UwCGAQAGAAUJIw6fJACcAAAAAA==.',
['Rë']='Rëquiëm:BAAALgADCgIJAgAAAA==.',
Sa='Saelbrine:BAAALgADCgEJAQAAAA==.Saeletar:BAAALgADCgcJBwAAAA==.Saihua:BAABLgAECn8WAAMUAAcJWg6YQgBAAQAUAAcJWg6YQgBAAQAjAAMJBQWhawBJAAAAAA==.Saintjohn:BAABLgAECn8gAAIIAAgJkxPNGAC8AQAIAAgJkxPNGAC8AQAAAA==.Saintjon:BAAALgAECgkJDQAAAA==.Saintrob:BAAALgAECgEJAgAAAA==.Salamando:BAACLgAFFH8ZAAMcAAcJMBoYBgAGAgAcAAcJuhkYBgAGAgAKAAUJpRSiAgBaAQAuAAQKfyEAAxwACQkOIAILAMYCABwACAnhHwILAMYCAAoABQnJINAUAJ0BAAAA.Sassparilluh:BAAALgADCgIJAgAAAA==.',
Sc='Scaryspices:BAAALgADCgIJAgAAAA==.Schlacht:BAAALgAFFAEJAQAAAA==.Scholoman:BAABLgAECn8bAAMVAAgJPCHqCAC3AgAVAAgJPCHqCAC3AgAHAAMJORIU4gCBAAAAAA==.Scumdog:BAAALgAECggJCAAAAA==.',
Se='Senpai:BAACLgAFFH8YAAIBAAYJYBtNCwDDAQABAAYJYBtNCwDDAQAuAAQKfyUAAgEACAkiJJohAO0CAAEACAkiJJohAO0CAAAA.',
Sh='Shackleßolt:BAAALgAECgEJAgABLgAECggJHwATAJQSAA==.Shadowborn:BAACLgAFFH8IAAIOAAQJahqZKQBfAQAOAAQJahqZKQBfAQAuAAQKfyoAAw4ACQn1HzwNAMgCAA4ACQn1HzwNAMgCABEAAwnXHaQQAOkAAAAA.Shalanthra:BAAALgAECgMJAwAAAA==.Shamallow:BAAALgADCgMJAQAAAA==.Shamanette:BAAALgADCgkJDwABLgAECgYJDQAeAAAAAA==.Shammunition:BAABLgAECn8pAAIlAAkJbSbIAAAfAwAlAAkJbSbIAAAfAwABLgAFFAMJBgAOAB0WAA==.Shanks:BAAALgADCgEJAQABLgAFFAQJCAADAAURAA==.Shaqueefa:BAAALgAECgIJAgAAAA==.Shartner:BAAALgADCgEJAQAAAA==.Shartz:BAABLgAECn8hAAIZAAgJrxZoKwDfAQAZAAgJrxZoKwDfAQAAAA==.Shaysa:BAEBLgAECn8cAAMTAAcJ0RLrJQBsAQATAAcJ0RLrJQBsAQACAAQJ6wn6SgCIAAAAAA==.Sheraa:BAAALgAECgYJCwAAAA==.Shinigamisan:BAABLgAECn8wAAIBAAkJkRJ1PgDfAQABAAkJkRJ1PgDfAQAAAA==.Shinycoco:BAAALgADCgcJBwAAAA==.Shynox:BAABLgAECn8iAAMHAAgJERueKwAKAgAHAAgJERueKwAKAgAVAAIJgxiLewCLAAAAAA==.',
Si='Sisirinah:BAAALgAECgQJBAAAAA==.Sitharco:BAABLgAECn8VAAIkAAgJZQ7qGgBkAQAkAAgJZQ7qGgBkAQAAAA==.',
Sk='Skag:BAACLgAFFH8iAAQOAAYJFh4hDgDHAQAOAAUJFh4hDgDHAQARAAEJ4wM/EwA4AAASAAEJAAAlNgAAAAAuAAQKfysAAw4ACQlMI4EWAPUCAA4ACQlMI4EWAPUCABEAAQlMImsVAD8AAAAA.Skarlotta:BAAALgADCgkJIgAAAA==.',
Sm='Smedley:BAAALgADCgcJBwAAAA==.Smorc:BAAALgAECgcJDQAAAA==.',
Sn='Snackwitch:BAABLgAECn8gAAIBAAcJIBdCUwCgAQABAAcJIBdCUwCgAQAAAA==.Snapgabagura:BAAALgAECggJEwAAAA==.Sncbmspd:BAAALgADCgUJBQAAAA==.Sneaki:BAABLgAECn8WAAQpAAgJvhvSBACzAQApAAUJEyDSBACzAQAiAAUJehQzEgC7AAAkAAEJMQXsYgAuAAABLgAECggJGAADAF8jAA==.Snixa:BAAALgADCgEJAQAAAA==.Snowproblem:BAAALgAECgQJBgAAAA==.',
So='Solarscar:BAAALgADCgkJEQAAAA==.Sommin:BAAALgAECgQJBgAAAA==.Sophelna:BAAALgADCgkJCQAAAA==.Sorno:BAAALgAECgUJCQAAAA==.Sorscha:BAAALgAECgUJBwAAAA==.Souljin:BAABLgAECn8hAAIJAAgJhQU3dwAOAQAJAAgJhQU3dwAOAQAAAA==.Soulviper:BAACLgAFFH8MAAIUAAMJGhdPEQDdAAAUAAMJGhdPEQDdAAAuAAQKfyAAAxQACQmyIQwDAEwDABQACQmyIQwDAEwDACMAAQnZBfOOACkAAAAA.',
Sp='Spankmaster:BAAALgAECgYJCQAAAA==.Spankmyflank:BAAALgAECgQJBAABLgAECgYJDQAeAAAAAA==.Spankshubby:BAAALgADCgkJFgAAAA==.Spiritbear:BAAALgAECgQJBQAAAA==.Sproe:BAAALgAECgUJBQABLgAECgcJFQAkAKoPAA==.Spurb:BAAALgAECgkJBwAAAA==.',
Sq='Squaleon:BAABLgAECn8VAAIHAAgJKgfLewArAQAHAAgJKgfLewArAQAAAA==.',
St='Stabbyfinch:BAABLgAECn8cAAIiAAcJFBXFBwCMAQAiAAcJFBXFBwCMAQAAAA==.Starthirteen:BAABLgAECn8hAAIZAAgJ9RNzOQCkAQAZAAgJ9RNzOQCkAQAAAA==.Steatfox:BAAALgADCgMJAwAAAA==.Stelf:BAAALgADCgQJBAABLgAECggJGwAEAKUkAA==.Steplok:BAAALgAECgkJEQAAAA==.Steroidz:BAAALgADCgEJAQAAAA==.Stonestriker:BAABLgAECn8aAAInAAcJpwj2IAD6AAAnAAcJpwj2IAD6AAAAAA==.Stoobendh:BAAALgAECgEJAQAAAA==.Stranglehold:BAAALgAECgQJCQAAAA==.Strixz:BAAALgADCgMJAwAAAA==.Sturge:BAAALgAECgYJEwAAAA==.',
Su='Supahsayajin:BAEALgAECgMJBAABLgAECgUJBQAeAAAAAA==.Survival:BAAALgADCgcJBwABLgAECgcJCAAeAAAAAA==.',
Sw='Sweetapple:BAAALgAECgMJBgAAAA==.Sweetbee:BAABLgAECn8hAAIZAAgJUQ1mQgCDAQAZAAgJUQ1mQgCDAQAAAA==.Sweetivy:BAAALgAECgQJBwAAAA==.Sweetpotato:BAAALgADCgMJBQAAAA==.Swole:BAABLgAECn8lAAIHAAkJVxj+IAA+AgAHAAkJVxj+IAA+AgAAAA==.Swoleefist:BAEBLgAECn8fAAINAAgJ+gguLQAXAQANAAgJ+gguLQAXAQAAAA==.',
Sy='Syanalody:BAAALgAECgQJCwAAAA==.Syanaria:BAAALgADCgcJDwABLgAECgEJAQAeAAAAAA==.Sylarz:BAAALgAECgIJAwABLgAFFAQJCAAJAIkUAA==.Syn:BAABLgAECn8yAAQLAAkJyiKdAgA9AgAJAAkJpBxqFQBrAgALAAcJTiOdAgA9AgAMAAMJWRpUOwDHAAAAAA==.Synthica:BAAALgADCgUJBgABLgAECggJGgAhAB0kAA==.',
Sz='Szayelaporro:BAAALgADCgcJBwAAAA==.',
['Sð']='Sðrrøw:BAAALgADCgcJBwAAAA==.',
Ta='Talyeria:BAAALgADCgUJBwAAAA==.Tanstaafl:BAABLgAECn8vAAIZAAkJcRi0GABFAgAZAAkJcRi0GABFAgAAAA==.Taralom:BAABLgAECn8YAAImAAcJfgsQKwAlAQAmAAcJfgsQKwAlAQAAAA==.Tasselhoff:BAAALgADCgQJBAAAAA==.Taz:BAEBLgAECn8qAAIfAAgJNCVWAQDfAgAfAAgJNCVWAQDfAgAAAA==.Tazroc:BAAALgADCgMJAwABLgADCgQJBAAeAAAAAA==.',
Te='Tehrocklee:BAAALgADCgcJDgAAAA==.Telmo:BAABLgAECn8+AAMIAAkJ0RtZDgB3AgAIAAgJ3htZDgB3AgAgAAkJHBcZCwBqAgAAAA==.Tenebrix:BAAALgAECgMJAwAAAA==.Teracgosa:BAABLgAECn8UAAMbAAYJHAL8IQCWAAAbAAYJHAL8IQCWAAAKAAMJnQWHNABwAAAAAA==.Teuton:BAAALgAECgYJBwAAAA==.',
Th='Thadex:BAABLgAECn8eAAMnAAcJWyXkBAB4AgAnAAcJWyXkBAB4AgAFAAIJZSWESgDIAAAAAA==.Thassa:BAAALgAECgYJEAAAAA==.Thearch:BAAALgAECgEJAQABLgAECgcJMQAhAMkVAA==.Thecolonel:BAAALgADCgUJBQAAAA==.Theholytank:BAAALgAECgEJAQAAAA==.Thepallyguy:BAAALgAECgUJBgABLgAECgcJGQAgACQjAA==.Thepriestguy:BAABLgAECn8ZAAMgAAcJJCPLDABKAgAgAAcJwh7LDABKAgAIAAUJEyNfHQDzAQAAAA==.Therat:BAAALgADCgIJAgAAAA==.Thorseas:BAABLgAECn8nAAIPAAgJUSK7CQBEAgAPAAgJUSK7CQBEAgAAAA==.Thundastruck:BAAALgADCgEJAQAAAA==.Thunderkill:BAAALgAECgYJCgAAAA==.',
Ti='Tiertrah:BAAALgADCgUJBQAAAA==.Tiger:BAAALgAECgYJDAAAAA==.Titùs:BAACLgAFFH8GAAIBAAMJnAMOZADPAAABAAMJnAMOZADPAAAuAAQKfyIAAgEACAk6EfxtAPkBAAEACAk6EfxtAPkBAAAA.',
To='Tooyoo:BAACLgAFFH8ZAAMFAAYJTyBsAQDyAQAFAAUJbCFsAQDyAQAnAAUJtR5RBgBqAQAuAAQKfx0AAwUACQnMIxMIACkDAAUACAlhJBMIACkDACcABAmaIesrALkAAAAA.Torpedotaka:BAAALgAECgYJEQAAAA==.',
Tp='Tpala:BAAALgAECgcJEAAAAA==.',
Ts='Tsukirius:BAAALgAECgEJAQABLgAECgkJOAAXAH0dAA==.',
Tu='Tulkas:BAAALgAECgEJAwAAAA==.Turthunt:BAACLgAFFH8aAAQPAAgJzxsQAQDxAQAQAAcJYBuHAgA5AgAPAAYJJh8QAQDxAQAZAAIJjxI/FwCqAAAuAAQKfy4ABBAACQlFJq8CAIUDABAACAlWJq8CAIUDAA8ABwkEJEoKADoCABkAAQl5Ja6rAG0AAAAA.Turtlock:BAACLgAFFH8FAAIJAAMJxxzFQgABAQAJAAMJxxzFQgABAQAuAAQKfx8AAgkACQl8Id0EAG0DAAkACQl8Id0EAG0DAAEuAAUUCAkaAA8AzxsA.',
Tw='Twinkdaddy:BAABLgAECn8dAAQCAAkJmhANFQC+AQACAAkJmhANFQC+AQATAAYJHAslPAD0AAANAAIJ3wBJigAxAAAAAA==.Twinns:BAAALgADCgQJBAAAAA==.Twoyoo:BAAALgAFFAIJAgABLgAFFAYJGQAFAE8gAA==.',
Ty='Tyelock:BAAALgAECgUJAwAAAA==.Tygr:BAAALgAFFAEJAQAAAA==.Tyndriel:BAAALgAECgUJBwAAAA==.Tyremon:BAAALgADCgYJBgAAAA==.Tyrraell:BAAALgADCgMJAwAAAA==.',
Uk='Ukai:BAAALgADCgcJBwAAAA==.',
Un='Uninclined:BAAALgAECgEJAQAAAA==.Unsurpassed:BAAALgAECgIJBAAAAA==.',
Va='Valaid:BAABLgAECn8mAAIEAAkJWR0mBgCJAgAEAAkJWR0mBgCJAgAAAA==.Valakar:BAAALgAECgUJBgAAAA==.Valoth:BAAALgAECgYJEgAAAA==.Vanelura:BAABLgAECn8YAAIHAAYJngcipADkAAAHAAYJngcipADkAAAAAA==.Vannarcis:BAAALgADCggJCAAAAA==.',
Ve='Vesi:BAAALgAECgcJCAAAAA==.Veyle:BAAALgAECgUJCQAAAA==.',
Vi='Villager:BAAALgADCgcJBwAAAA==.Vistray:BAAALgAECgEJAQAAAA==.',
Vo='Voidsorrow:BAAALgADCgQJBAAAAA==.Volassian:BAAALgADCgIJAgAAAA==.',
Vr='Vrahalla:BAABLgAECn8UAAIOAAcJUBTnZwBMAQAOAAcJUBTnZwBMAQAAAA==.',
Vy='Vyrana:BAAALgAECgYJEwAAAA==.',
Wa='Wahstella:BAACLgAFFH8YAAIBAAcJ6BXWCgDIAQABAAcJ6BXWCgDIAQAuAAQKf0oAAgEACQkwJRgEAL8DAAEACQkwJRgEAL8DAAAA.Waraight:BAACLgAFFH8OAAISAAcJnxHtBABXAQASAAcJnxHtBABXAQAuAAQKfxsAAhIACAkiHm8MAEoCABIACAkiHm8MAEoCAAAA.Wararrior:BAABLgAFFH8IAAIhAAQJHx0LAwBrAQAhAAQJHx0LAwBrAQABLgAFFAcJDgASAJ8RAA==.Wasabi:BAACLgAFFH8IAAIDAAQJBREKFAAyAQADAAQJBREKFAAyAQAuAAQKfxoAAgMACAkzIogTAOMCAAMACAkzIogTAOMCAAAA.Waterdroplet:BAABLgAECn8iAAIHAAkJlBnYHQBQAgAHAAkJlBnYHQBQAgAAAA==.',
We='Weedcookies:BAAALgAECgQJBAAAAA==.',
Wh='Whitelady:BAABLgAECn8jAAImAAkJFBaJEAAGAgAmAAkJFBaJEAAGAgAAAA==.Whodofthunk:BAABLgAECn8VAAIZAAYJwBhtTABiAQAZAAYJwBhtTABiAQAAAA==.',
Wi='Wilferth:BAABLgAECn8rAAIhAAcJvhydDgCvAQAhAAcJvhydDgCvAQAAAA==.Winterhogman:BAAALgADCgYJDAABLgAECgcJHwAJABoRAA==.Wirl:BAAALgADCgEJAQAAAA==.',
Wo='Woozi:BAACLgAFFH8RAAIUAAUJ5BhCAwCmAQAUAAUJ5BhCAwCmAQAuAAQKfyAAAxQACAltIRQTAH0CABQACAltIRQTAH0CACMABQmTEAxLABsBAAAA.Worgasim:BAAALgAECgQJBAAAAA==.',
Wr='Wreckedon:BAAALgAECgMJAwAAAA==.Wrekker:BAAALgAECgYJBgAAAA==.Wrinklz:BAABLgAECn8mAAIBAAgJSxCbVACdAQABAAgJSxCbVACdAQAAAA==.',
Wu='Wulgarr:BAABLgAECn8aAAIhAAgJHSSlAgA9AwAhAAgJHSSlAgA9AwAAAA==.',
Xa='Xavierson:BAABLgAECn8XAAIFAAcJWwYiPQD/AAAFAAcJWwYiPQD/AAAAAA==.',
Xe='Xen:BAAALgAECgQJBQABLgAECgcJCAAeAAAAAA==.',
Xi='Xiaoxiao:BAAALgAECgQJBQAAAA==.Xilone:BAAALgAECggJEwAAAA==.',
Ya='Yangchengfu:BAABLgAECn8xAAIhAAcJyRUkFABeAQAhAAcJyRUkFABeAQAAAA==.',
Ye='Yelpies:BAAALgADCgUJBwABLgAECgcJCAAeAAAAAA==.',
Yi='Yi:BAAALgAECgcJCAAAAA==.',
Yo='Yoinksower:BAAALgAECgcJDwAAAA==.Yootoo:BAAALgAECgUJBQABLgAFFAYJGQAFAE8gAA==.Youkai:BAABLgAECn8qAAIOAAcJICJlJAAsAgAOAAcJICJlJAAsAgAAAA==.',
Za='Zaaga:BAABLgAECn8jAAMMAAgJLRDTIQBHAQAJAAgJ1Q2eTQBzAQAMAAYJ6g7TIQBHAQAAAA==.Zalarok:BAABLgAECn8ZAAIjAAcJyxv/GADHAQAjAAcJyxv/GADHAQABLgAFFAQJCAAJAIkUAA==.Zalianna:BAAALgADCgQJBAAAAA==.Zamon:BAAALgADCgkJCQAAAA==.Zamyk:BAAALgAECgcJDAAAAA==.Zarf:BAABLgAECn8pAAIPAAkJmw/ZEgDLAQAPAAkJmw/ZEgDLAQAAAA==.Zaviar:BAAALgAECgcJEgAAAA==.Zavyn:BAAALgADCgcJBwAAAA==.Zayra:BAAALgAECgYJBgAAAA==.',
Ze='Zeld:BAAALgAECgcJEAABLgAFFAQJCwAFAGkeAA==.Zelgius:BAACLgAFFH8GAAIOAAIJ0CGidQC9AAAOAAIJ0CGidQC9AAAuAAQKfzgAAg4ACAkBJsgLAD0DAA4ACAkBJsgLAD0DAAAA.Zenasdara:BAAALgAECgMJAgAAAA==.Zenerap:BAAALgAECgEJAQAAAA==.Zenhunter:BAABLgAECn8hAAIZAAgJFSAXFwBRAgAZAAgJFSAXFwBRAgAAAA==.Zevilna:BAABLgAECn8hAAIUAAcJUSMCCwC9AgAUAAcJUSMCCwC9AgAAAA==.',
Zh='Zhongfu:BAABLgAECn8mAAICAAgJMhRLHAD5AQACAAgJMhRLHAD5AQAAAA==.Zhulee:BAACLgAFFH8MAAICAAQJBh8uBQB4AQACAAQJBh8uBQB4AQAuAAQKfyMAAgIACQnHI+YDAOUCAAIACQnHI+YDAOUCAAAA.',
Zi='Zikaja:BAACLgAFFH8mAAINAAYJYBIoBgBxAQANAAYJYBIoBgBxAQAuAAQKfysAAg0ACQkUGQIPAKcCAA0ACQkUGQIPAKcCAAAA.Zins:BAAALgADCgQJBAAAAA==.Zinu:BAAALgAECgEJAQAAAA==.Zir:BAAALgAECgEJBAAAAA==.Ziviana:BAACLgAFFH8hAAIWAAgJWx6PAAARAwAWAAgJWx6PAAARAwAuAAQKfysAAhYACQlTI3QEAEcDABYACQlTI3QEAEcDAAAA.',
Zo='Zoark:BAAALgADCgEJAQAAAA==.Zorgap:BAAALgAFFAEJAQAAAA==.Zoryp:BAAALgADCgIJAgAAAA==.',
Zu='Zuldope:BAABLgAECn8fAAQjAAkJcwlMKABVAQAjAAkJcwlMKABVAQAUAAgJzQUmTAAaAQAlAAEJuANBKQApAAAAAA==.',
Zv='Zv:BAACLgAFFH8QAAQOAAUJuB0lMQBQAQAOAAQJrhslMQBQAQARAAQJsxElBQAyAQASAAEJAABUNgAAAAAuAAQKfxgAAw4ACAmfIlccANQCAA4ACAnOIVccANQCABEABwn4HyIEAB8CAAAA.',
Zy='Zyprexal:BAABLgAECn8bAAMWAAcJcSAxFgCFAgAWAAcJcSAxFgCFAgAXAAYJ4BUoNgBjAQAAAA==.',
['Zï']='Zïlla:BAAALgADCgYJBgAAAA==.Zïn:BAAALgAECgMJBQAAAA==.',
['Ðr']='Ðraven:BAAALgAECgkJBwAAAA==.',
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
